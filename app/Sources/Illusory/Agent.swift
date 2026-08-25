import Foundation

/// Works out what to do, then does it — and when a step fails, tells the model what
/// went wrong and lets it correct itself rather than giving up.
///
/// Bounded on purpose. The one-second rule is the product, so the agent gets a small
/// number of steps, a small number of repairs, and a hard wall-clock ceiling. If it
/// cannot finish inside those, the honest answer is that this was never a job for
/// Illusory.
enum Agent {
    static let maxSteps = 8
    static let maxRepairs = 3
    static let deadline: TimeInterval = 30

    static let nothing = "Nothing obvious to finish."

    struct Plan {
        let summary: String
        let confidence: Double
        let basis: String
        let steps: [Step]

        var isActionable: Bool { confidence >= 0.55 && !steps.isEmpty && !summary.isEmpty }
        var isHighRisk: Bool { steps.contains(where: \.isHighRisk) }

        /// What the user sees while holding: the intent, then the literal first
        /// things that will run.
        var previewCaption: String {
            let detail = steps.prefix(2).map(\.preview).joined(separator: " · ")
            let more = steps.count > 2 ? " · +\(steps.count - 2) more" : ""
            return detail.isEmpty ? summary : "\(summary)\n\(detail)\(more)"
        }
    }

    // MARK: - Prompt

    private static var system: String {
        """
        You are Illusory. The user pressed one key while working. Infer the single \
        small step they were about to take themselves, and carry it out.

        HOW TO READ THE CONTEXT, in priority order:
        1. An unfinished pattern in recent activity or recent file changes. If two \
        files were renamed to a new scheme minutes ago and siblings still use the \
        old one, the step is finishing that rename. This is the strongest signal.
        2. Something the user has typed that is not yet true. "logo's attached" in \
        a message means attach the logo. Treat what they wrote as a promise to keep.
        3. An obvious next action in the focused field, given its contents and caret.
        4. The screenshot, for state the text context missed. Screen coordinates in \
        the screenshot are scaled — prefer files, keys and scripting over clicking \
        at coordinates whenever either would do.

        HARD LIMITS:
        - Only ever do something that would take a person about thirty seconds. \
        Never a project, never a multi-step plan needing judgement, never anything \
        requiring clarification.
        - Never redo something the user has plainly already done.
        - Never merely press a key or click a button they are already looking at. \
        That is not help.
        - Prefer the narrowest tool that works. Use shell only when no file or app \
        tool fits, and never for anything destructive or networked.
        - If the evidence is thin, return no steps with low confidence. Saying \
        nothing is correct and expected. Inventing a plausible action is the worst \
        possible outcome.

        TOOLS — each step is {"tool": name, ...args}:
        \(Tools.catalogue)

        Reply with JSON only, no fences, no prose:
        {"summary": "<imperative sentence, max 12 words>",
         "confidence": <0.0-1.0>,
         "basis": "<the one signal you used, under 10 words>",
         "steps": [{"tool": "...", ...}]}
        """
    }

    // MARK: - Planning

    static func plan(_ snapshot: ContextSnapshot) async throws -> Plan {
        let raw = try await Model.complete(system: system,
                                           user: snapshot.promptDescription,
                                           imageBase64JPEG: snapshot.screenshot)
        return parse(raw)
    }

    /// Models wrap JSON in fences despite instructions, so unwrap before decoding.
    /// An unparseable reply yields no steps — nothing unstructured is ever executed.
    static func parse(_ raw: String) -> Plan {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Plan(summary: raw, confidence: 0, basis: "unstructured reply", steps: [])
        }
        return Plan(summary: (json["summary"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                    confidence: (json["confidence"] as? NSNumber)?.doubleValue ?? 0.5,
                    basis: json["basis"] as? String ?? "",
                    steps: steps(from: json["steps"]))
    }

    private static func steps(from value: Any?) -> [Step] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let tool = item["tool"] as? String, !tool.isEmpty else { return nil }
            return Step(tool: tool, args: item)
        }
        .prefix(maxSteps)
        .map { $0 }
    }

    // MARK: - Execution

    /// Runs the plan, reporting progress as it goes. A failing step is not the end:
    /// the error goes back to the model with what has already happened, and it gets
    /// a bounded number of attempts to put it right.
    @MainActor
    static func execute(_ plan: Plan,
                        context snapshot: ContextSnapshot,
                        progress: @MainActor (String) -> Void) async -> String {
        var queue = plan.steps
        var completed: [String] = []
        var repairs = 0
        var last = "Done."
        let started = Date()

        while !queue.isEmpty {
            guard Date().timeIntervalSince(started) < deadline else {
                return "Stopped — took too long."
            }
            let step = queue.removeFirst()
            progress(step.preview)

            do {
                last = try await Tools.run(step)
                completed.append("\(step.tool): ok — \(last.prefix(80))")
                Log.info("step ok · \(step.tool) · \(last.prefix(80))")
            } catch {
                let reason = error.localizedDescription
                Log.info("step failed · \(step.tool) · \(reason)")
                completed.append("\(step.tool): FAILED — \(reason)")

                guard repairs < maxRepairs else {
                    return "Gave up: \(reason)"
                }
                repairs += 1
                progress("That didn't work — trying another way…")

                do {
                    let fixed = try await repair(snapshot, failed: step,
                                                 reason: reason, done: completed)
                    guard !fixed.isEmpty else { return "Couldn't do it: \(reason)" }
                    Log.info("repair \(repairs): \(fixed.map(\.tool).joined(separator: ", "))")
                    queue = fixed + queue
                } catch {
                    return "Couldn't do it: \(reason)"
                }
            }
        }
        return last
    }

    /// Asks for a correction, given what was attempted and how it failed.
    private static func repair(_ snapshot: ContextSnapshot,
                               failed: Step, reason: String,
                               done: [String]) async throws -> [Step] {
        let prompt = """
        \(snapshot.promptDescription)

        ---

        You were carrying out a step and it failed.

        Failed step: \(jsonString(failed.args))
        Error: \(reason)

        What has happened so far:
        \(done.joined(separator: "\n"))

        Fix it. Return the replacement steps only — do not repeat work already done.
        If the error means the task cannot be done, return an empty steps array.
        Reply with JSON only: {"steps": [{"tool": "...", ...}]}
        """
        let raw = try await Model.complete(system: system, user: prompt, maxTokens: 700)
        return parse(raw).steps
    }

    private static func jsonString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "\(value)" }
        return text
    }
}

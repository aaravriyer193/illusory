import Foundation

/// Works out what to do, then does it — and when a step fails, tells the model what
/// went wrong and lets it correct itself rather than giving up.
///
/// Bounded on purpose. The one-second rule is the product, so the agent gets a small
/// number of steps, a small number of repairs, and a hard wall-clock ceiling. If it
/// cannot finish inside those, the honest answer is that this was never a job for
/// Illusory.
enum Agent {
    static let maxSteps = 12
    static let maxRepairs = 3
    /// How many times Illusory may look again and carry on. One pass can only ever
    /// act on what was true before it started — clicking a field, for instance,
    /// changes what the next step should be.
    static let maxRounds = 8
    /// A backstop against a genuinely stuck loop, not a limit on how long real
    /// work may take. The user has a stop button; cutting off a run that is
    /// making progress is worse than letting it run on.
    static let deadline: TimeInterval = 600

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
        4. The screenshot, for state the text context missed.

        CLICKING. To click something, use click_element with the label of one of \
        the controls listed in the context. Those carry real coordinates from the \
        system and are always correct. Do NOT estimate coordinates from the \
        screenshot — you are bad at it, and a wrong guess clicks something else \
        entirely. Raw click{x,y} is a last resort for when the target is not in \
        that list, and its coordinates are in the screenshot's own pixel space, \
        measured from the top-left. Better still, prefer files, keys and scripting \
        over clicking whenever any of them would do the same job.

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

        Give every step the task needs, not just the first one. Filling a field is \
        click_element then key{cmd+a} then type — three steps, one plan. Illusory \
        will look at the screen again after your steps run and you can add more \
        then, so never stop early on purpose, and never stop after a single click.

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
        var completedAcrossRounds: [String] = []
        var result = "Done."
        let deadlineAt = Date().addingTimeInterval(deadline)
        var current = plan

        for round in 0..<maxRounds {
            if Task.isCancelled { return "Stopped." }
            let outcome = await runOnce(current, context: snapshot,
                                        deadlineAt: deadlineAt, progress: progress)
            completedAcrossRounds += outcome.log
            result = outcome.result
            if outcome.stopped { return result }
            guard Date() < deadlineAt else { return result }

            // Look again. The screen has changed, and whether anything remains can
            // only be answered against what is true now.
            progress("Checking…")
            let fresh = await ContextSnapshot.full()
            guard let next = try? await continuation(fresh, goal: plan.summary,
                                                     done: completedAcrossRounds),
                  !next.isEmpty else {
                Log.info("agent: finished after \(round + 1) round(s)")
                return result
            }
            Log.info("agent: round \(round + 2) — \(next.map(\.tool).joined(separator: ", "))")
            current = Plan(summary: plan.summary, confidence: plan.confidence,
                           basis: plan.basis, steps: next)
        }
        return result
    }

    /// Asks whether the goal is actually met, and what remains if not.
    private static func continuation(_ snapshot: ContextSnapshot,
                                     goal: String, done: [String]) async throws -> [Step] {
        let prompt = """
        \(snapshot.promptDescription)

        ---

        The goal was: \(goal)

        Steps carried out so far:
        \(done.joined(separator: "\n"))

        Look at the screen as it is NOW. If the goal is fully achieved, return an \
        empty steps array — that is the expected answer and you should give it \
        readily. If something still genuinely remains, return only the remaining \
        steps. Never repeat work already done.

        Reply with JSON only: {"steps": [{"tool": "...", ...}]}
        """
        let raw = try await Model.complete(system: system, user: prompt,
                                           imageBase64JPEG: snapshot.screenshot,
                                           maxTokens: 700)
        return parse(raw).steps
    }

    /// One pass through a queue of steps, repairing failures as it goes.
    @MainActor
    private static func runOnce(_ plan: Plan,
                                context snapshot: ContextSnapshot,
                                deadlineAt: Date,
                                progress: @MainActor (String) -> Void)
        async -> (result: String, log: [String], stopped: Bool) {
        var queue = plan.steps
        var completed: [String] = []
        var repairs = 0
        var last = "Done."

        while !queue.isEmpty {
            guard Date() < deadlineAt else {
                return ("Stopped — took too long.", completed, true)
            }
            if Task.isCancelled { return ("Stopped.", completed, true) }
            let step = queue.removeFirst()
            progress(step.preview)

            do {
                last = try await Tools.run(step)
                completed.append("\(step.tool): ok — \(last.prefix(80))")
                Log.info("step ok · \(step.tool) · \(last.prefix(80))")
                // The next step reads the screen the previous one just changed,
                // so give the app time to finish changing it.
                try? await Task.sleep(for: .milliseconds(500))
            } catch {
                let reason = error.localizedDescription
                Log.info("step failed · \(step.tool) · \(reason)")
                completed.append("\(step.tool): FAILED — \(reason)")

                guard repairs < maxRepairs else {
                    return ("Gave up: \(reason)", completed, true)
                }
                repairs += 1
                progress("That didn't work — trying another way…")

                do {
                    let fixed = try await repair(snapshot, failed: step,
                                                 reason: reason, done: completed)
                    guard !fixed.isEmpty else {
                        return ("Couldn't do it: \(reason)", completed, true)
                    }
                    Log.info("repair \(repairs): \(fixed.map(\.tool).joined(separator: ", "))")
                    queue = fixed + queue
                } catch {
                    return ("Couldn't do it: \(reason)", completed, true)
                }
            }
        }
        return (last, completed, false)
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

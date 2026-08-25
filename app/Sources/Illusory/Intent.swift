import Foundation

/// Turns a snapshot into the one small step the user was about to take themselves.
///
/// The model returns structured JSON rather than a sentence, because a free-text
/// model will always produce *something* — and something plausible-sounding on thin
/// evidence is exactly the failure that makes a tool like this untrustworthy. A
/// confidence score gives Illusory the ability to say nothing.
enum Intent {
    struct Proposal {
        let summary: String
        let confidence: Double
        let basis: String
        let action: Action

        var isActionable: Bool {
            guard confidence >= 0.55, !summary.isEmpty else { return false }
            if case .none = action { return false }
            return true
        }

        /// The preview caption: what will happen, and the literal thing that will
        /// run. A preview that only paraphrases the action is not a preview.
        var previewCaption: String {
            let detail = action.preview
            return detail.isEmpty ? summary : "\(summary)\n\(detail)"
        }
    }

    static let nothing = "Nothing obvious to finish."

    static let system = """
    You are Illusory. The user pressed one key while working. Infer the single small \
    step they were about to take themselves, and describe it in one short imperative \
    sentence of at most 12 words.

    HOW TO READ THE CONTEXT, in priority order:
    1. An unfinished pattern in recent activity or recent file changes. If two files \
    were renamed to a new scheme minutes ago and siblings still use the old one, the \
    step is finishing that rename. This is the strongest signal there is.
    2. A statement the user has typed that is not yet true. "logo's attached" in a \
    message means attach the logo. Treat what they wrote as a promise to fulfil.
    3. An obvious next action in the focused field, given its contents and caret.
    4. The screenshot, for state the text context missed.

    HARD LIMITS:
    - Only ever propose something that would take a person about thirty seconds. \
    Never a project, never a multi-step plan, never anything needing clarification.
    - Never propose something the user has plainly already done.
    - Never propose merely continuing to type, pressing a key, or clicking a button \
    they are already looking at. That is not help.
    - If the evidence is thin, say so with low confidence. Saying nothing is correct \
    and expected; inventing a plausible action is the worst possible outcome.

    You do not describe the step — you carry it out. Choose exactly one tool:

    - "rename": renaming or renumbering files. Give absolute "from" paths and the new \
    "to" names. Preferred whenever the task is files: it is checked and reversible.
    - "type": insert text at the caret, exactly as the user would have typed it.
    - "replace_selection": replace what is currently selected.
    - "shell": anything else on disk. One command. Never destructive, never network, \
    never sudo. Quote every path.
    - "applescript": driving another app when nothing else fits.
    - "none": the evidence is thin, or nothing needs doing. This is a good answer.

    Reply with JSON only, no fences, no prose:
    {"action": "<imperative sentence>", "confidence": <0.0-1.0>,
     "basis": "<the one signal you used, under 10 words>",
     "tool": "rename|type|replace_selection|shell|applescript|none",
     "rename": [{"from": "/abs/path", "to": "newname.ext"}],
     "text": "<for type / replace_selection>",
     "shell": {"command": "...", "cwd": "/abs/dir"},
     "applescript": "..."}

    Include only the key belonging to the tool you chose.
    """

    static func propose(_ snapshot: ContextSnapshot) async throws -> Proposal {
        let raw = try await OpenRouter.complete(system: system,
                                                user: snapshot.promptDescription,
                                                imageBase64JPEG: snapshot.screenshot)
        return parse(raw)
    }

    /// Models wrap JSON in fences despite instructions, so unwrap before decoding
    /// and fall back to treating the whole reply as the action.
    static func parse(_ raw: String) -> Proposal {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let action = json["action"] as? String
        else {
            // An unparseable reply is never executed: no structure, no action.
            return Proposal(summary: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                            confidence: 0, basis: "unstructured reply", action: .none)
        }
        return Proposal(summary: action.trimmingCharacters(in: .whitespacesAndNewlines),
                        confidence: (json["confidence"] as? NSNumber)?.doubleValue ?? 0.5,
                        basis: json["basis"] as? String ?? "",
                        action: Action.parse(json))
    }
}

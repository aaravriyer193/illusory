import Foundation

/// Turns a snapshot into the one small step the user was about to take themselves.
///
/// The model returns structured JSON rather than a sentence, because a free-text
/// model will always produce *something* — and something plausible-sounding on thin
/// evidence is exactly the failure that makes a tool like this untrustworthy. A
/// confidence score gives Illusory the ability to say nothing.
enum Intent {
    struct Proposal {
        let action: String
        let confidence: Double
        let basis: String

        var isActionable: Bool { confidence >= 0.55 && !action.isEmpty }
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

    Reply with JSON only, no fences, no prose:
    {"action": "<imperative sentence>", "confidence": <0.0-1.0>, "basis": "<the one \
    signal you used, under 10 words>"}
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
            return Proposal(action: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                            confidence: 0.5, basis: "unstructured reply")
        }
        let confidence = (json["confidence"] as? NSNumber)?.doubleValue ?? 0.5
        return Proposal(action: action.trimmingCharacters(in: .whitespacesAndNewlines),
                        confidence: confidence,
                        basis: json["basis"] as? String ?? "")
    }
}

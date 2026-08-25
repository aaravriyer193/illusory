import Foundation

/// Illusory's model access. Routed through OpenRouter so the intent model can be
/// swapped without a rebuild — the gesture's budget matters far more than the
/// model's ceiling, so this should always point at something fast.
enum OpenRouter {
    enum RouterError: LocalizedError {
        case noKey
        case http(Int, String)
        case malformed
        case emptyContent
        case timedOut

        var errorDescription: String? {
            switch self {
            case .noKey: return "No OpenRouter key set."
            case .http(let code, let body): return "OpenRouter \(code): \(body)"
            case .malformed: return "Unexpected response from OpenRouter."
            case .emptyContent: return "Model returned nothing — reasoning used the whole budget."
            case .timedOut: return "Took too long — Illusory gave up."
            }
        }
    }

    static var apiKey: String? { Env["OPENROUTER_API_KEY"] }
    static var model: String { Env["OPENROUTER_MODEL"] ?? "google/gemini-2.0-flash-001" }
    static var isConfigured: Bool { apiKey != nil }

    /// Hard budget. The one-second rule is the product, so a slow model is a bug,
    /// not something to wait out.
    static let budget: TimeInterval = 6.0

    /// `maxTokens` has to cover reasoning tokens too: a reasoning model spends them
    /// before it writes any content, and a tight cap comes back with an empty string
    /// rather than an error.
    /// Vision models take content as parts; text-only models take a plain string.
    /// Sending parts to a text model errors, so this only switches when there's an
    /// image to send.
    private static func userContent(_ text: String, _ image: String?) -> Any {
        guard let image else { return text }
        return [
            ["type": "text", "text": text],
            ["type": "image_url",
             "image_url": ["url": "data:image/jpeg;base64,\(image)"]],
        ]
    }

    static func complete(system: String, user: String, imageBase64JPEG: String? = nil,
                         maxTokens: Int = 400) async throws -> String {
        guard let apiKey else { throw RouterError.noKey }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = budget
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://illusory.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Illusory", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": 0.2,
            // Reasoning models spend the whole token budget thinking and return
            // empty content — measured at 4.9s and nothing to show for it. The
            // gesture cannot afford either.
            "reasoning": ["enabled": false],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent(user, imageBase64JPEG)],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RouterError.http(code, String(body.prefix(180)))
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw RouterError.malformed }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RouterError.emptyContent }
        return trimmed
    }
}

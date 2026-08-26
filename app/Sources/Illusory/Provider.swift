import Foundation

/// Where inference happens. OpenRouter by default; Ollama for anyone who would
/// rather nothing left the machine at all — which for a tool that reads your screen
/// is a reasonable thing to want.
enum Provider: String, CaseIterable, Identifiable {
    case openRouter
    case ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openRouter: return "Default"
        case .ollama:     return "Ollama (local)"
        }
    }

    var detail: String {
        switch self {
        case .openRouter: return "Fast, hosted, ready to go"
        case .ollama:     return "Private, needs Ollama running"
        }
    }

    var defaultModel: String {
        switch self {
        // Must be vision-capable: every gesture sends a screenshot, and a
        // text-only model would silently discard it.
        case .openRouter: return "xiaomi/mimo-v2.5"
        case .ollama:     return "qwen2.5vl:7b"
        }
    }
}

/// User-visible settings, persisted. Deliberately tiny — every knob here is one
/// the user genuinely has to make a call on.
enum Settings {
    private static let defaults = UserDefaults.standard

    static var provider: Provider {
        get { Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .openRouter }
        set { defaults.set(newValue.rawValue, forKey: "provider") }
    }

    /// Falls back through the stored value, then `.env`, then the provider default,
    /// so a fresh install works without anyone configuring anything.
    static var model: String {
        get {
            switch provider {
            case .openRouter:
                // Not user-selectable. It has to be fast, vision-capable and
                // non-reasoning; a reasoning model spends the entire budget
                // thinking and returns empty content, which just looks broken.
                return provider.defaultModel
            case .ollama:
                let stored = defaults.string(forKey: "model.ollama") ?? ""
                return stored.isEmpty ? (Env["OLLAMA_MODEL"] ?? provider.defaultModel) : stored
            }
        }
        set {
            guard provider == .ollama else { return }
            defaults.set(newValue, forKey: "model.ollama")
        }
    }

    static var ollamaHost: String {
        get { defaults.string(forKey: "ollamaHost") ?? Env["OLLAMA_HOST"] ?? "http://127.0.0.1:11434" }
        set { defaults.set(newValue, forKey: "ollamaHost") }
    }

    static var holdThreshold: Double {
        get {
            let stored = defaults.double(forKey: "holdThreshold")
            return stored > 0 ? stored : 0.25
        }
        set { defaults.set(newValue, forKey: "holdThreshold") }
    }
}

enum ModelError: LocalizedError {
    case notConfigured(String)
    case http(Int, String)
    case malformed
    case empty

    var errorDescription: String? {
        switch self {
        case .notConfigured(let why): return why
        case .http(let code, let body): return "Model error \(code): \(body)"
        case .malformed: return "Unexpected response from the model."
        case .empty: return "Model returned nothing."
        }
    }
}

/// One call, whichever provider is selected.
enum Model {
    /// A shipped build has no `.env`, so it has no key — it goes through the
    /// site's proxy instead, which always exists. There is nothing for the user
    /// to configure either way.
    static var isConfigured: Bool { true }

    static func complete(system: String, user: String,
                         imageBase64JPEG: String? = nil,
                         maxTokens: Int = 900) async throws -> String {
        switch Settings.provider {
        case .openRouter:
            return try await openRouter(system, user, imageBase64JPEG, maxTokens)
        case .ollama:
            return try await ollama(system, user, imageBase64JPEG)
        }
    }

    // MARK: - OpenRouter

    private static func openRouter(_ system: String, _ user: String,
                                   _ image: String?, _ maxTokens: Int) async throws -> String {
        // With a key in .env, talk to OpenRouter directly — that is the developer
        // path, and it keeps one fewer hop in the latency budget. Without one,
        // which is every shipped build, go through the site.
        guard let key = Env["OPENROUTER_API_KEY"] else {
            return try await proxy(system, user, image, maxTokens)
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://illusory.fulmina.re", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Illusory", forHTTPHeaderField: "X-Title")

        // Vision models take content as parts; text-only models reject that shape,
        // so only switch when there is actually an image to send.
        let content: Any = image.map { image in
            [["type": "text", "text": user],
             ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image)"]]]
        } ?? user

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Settings.model,
            "max_tokens": maxTokens,
            "temperature": 0.1,
            // Reasoning models spend the entire budget thinking and return empty
            // content. The gesture cannot afford either the tokens or the seconds.
            "reasoning": ["enabled": false],
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": content]],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ModelError.http(code, String((String(data: data, encoding: .utf8) ?? "").prefix(160)))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String
        else { throw ModelError.malformed }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ModelError.empty }
        return trimmed
    }

    // MARK: - Site proxy

    /// Illusory's own endpoint, which holds the key. A distributed app cannot keep
    /// a secret, so it is not given one.
    private static func proxy(_ system: String, _ user: String,
                              _ image: String?, _ maxTokens: Int) async throws -> String {
        let site = Env["ILLUSORY_SITE"] ?? "https://illusory.fulmina.re"
        guard let url = URL(string: "\(site)/api/model") else {
            throw ModelError.notConfigured("Bad site URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["system": system, "user": user, "maxTokens": maxTokens]
        if let image { body["image"] = image }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard (200..<300).contains(code) else {
            let detail = (json?["error"] as? String)
                ?? String((String(data: data, encoding: .utf8) ?? "").prefix(160))
            throw ModelError.http(code, detail)
        }
        guard let text = json?["content"] as? String, !text.isEmpty else {
            throw ModelError.empty
        }
        return text
    }

    // MARK: - Ollama

    private static func ollama(_ system: String, _ user: String,
                               _ image: String?) async throws -> String {
        guard let url = URL(string: "\(Settings.ollamaHost)/api/chat") else {
            throw ModelError.notConfigured("Bad Ollama host.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var userMessage: [String: Any] = ["role": "user", "content": user]
        if let image { userMessage["images"] = [image] }

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Settings.model,
            "stream": false,
            "options": ["temperature": 0.1],
            "messages": [["role": "system", "content": system], userMessage],
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw ModelError.http(code, String((String(data: data, encoding: .utf8) ?? "").prefix(160)))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let text = message["content"] as? String
            else { throw ModelError.malformed }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ModelError.empty }
            return trimmed
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw ModelError.notConfigured("Ollama isn't running at \(Settings.ollamaHost).")
        }
    }
}

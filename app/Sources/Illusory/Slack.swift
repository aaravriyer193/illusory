import Foundation

/// Minimal Slack Web API client.
///
/// Illusory acts *as you*, not as a bot, so a user token (`xoxp-`) is preferred —
/// messages it sends come from you, and it can see what you can see. A bot token
/// (`xoxb-`) works too but is scoped to channels the bot has been invited to.
enum Slack {
    struct Identity { let user: String; let team: String; let userID: String }

    enum SlackError: LocalizedError {
        case noToken
        case api(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "No Slack token. Install your app to the workspace (Slack app → "
                     + "OAuth & Permissions → Install), then put the xoxp- token in .env "
                     + "as SLACK_USER_TOKEN."
            case .api(let code):
                return "Slack API error: \(code)"
            }
        }
    }

    static var token: String? { Env["SLACK_USER_TOKEN"] ?? Env["SLACK_BOT_TOKEN"] }
    static var isConfigured: Bool { token != nil }

    @discardableResult
    static func call(_ method: String, _ params: [String: String] = [:]) async throws -> [String: Any] {
        guard let token else { throw SlackError.noToken }

        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackError.api("unparseable response")
        }
        guard json["ok"] as? Bool == true else {
            throw SlackError.api(json["error"] as? String ?? "unknown")
        }
        return json
    }

    static func whoAmI() async throws -> Identity {
        let json = try await call("auth.test")
        return Identity(user: json["user"] as? String ?? "?",
                        team: json["team"] as? String ?? "?",
                        userID: json["user_id"] as? String ?? "?")
    }

    static func post(channel: String, text: String) async throws {
        try await call("chat.postMessage", ["channel": channel, "text": text])
    }
}

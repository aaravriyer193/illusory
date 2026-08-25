import AppKit
import Security

/// Token storage. Tokens are user credentials, so they live in the Keychain rather
/// than in a file next to the app — and never in `.env`, which is for Illusory's
/// own build-time configuration, not for anything belonging to the person using it.
enum Keychain {
    private static let service = "app.illusory.tokens"

    static func set(_ value: String, for account: String) {
        remove(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

/// Connecting a service.
///
/// The user never sees a token. Illusory opens a normal browser consent screen on
/// illusory.fulmina.re, which holds the client secrets server-side and does the code
/// exchange itself — a distributed Mac app cannot keep a secret, so it must not be
/// asked to. The finished token comes back through the `illusory://` URL scheme and
/// goes straight into the Keychain.
extension Notification.Name {
    static let illusoryConnectionsChanged = Notification.Name("illusory.connections.changed")
}

enum Connect {
    static let site = Env["ILLUSORY_SITE"] ?? "https://illusory.fulmina.re"

    static func begin(_ brand: Brand) {
        // A nonce the site echoes back, so a callback Illusory didn't ask for is
        // ignored rather than trusted.
        let state = UUID().uuidString
        UserDefaults.standard.set(state, forKey: "oauth.state.\(brand.rawValue)")

        guard let url = URL(string: "\(site)/api/auth/\(brand.rawValue)/start?state=\(state)") else {
            return
        }
        Log.info("connect: opening consent for \(brand.rawValue)")
        NSWorkspace.shared.open(url)
    }

    static func disconnect(_ brand: Brand) {
        Keychain.remove("\(brand.rawValue).token")
        Keychain.remove("\(brand.rawValue).account")
        Log.info("connect: disconnected \(brand.rawValue)")
        NotificationCenter.default.post(name: .illusoryConnectionsChanged, object: nil)
    }

    static func token(for brand: Brand) -> String? {
        Keychain.get("\(brand.rawValue).token")
    }

    /// Handles `illusory://auth?provider=…&token=…&account=…`.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard url.scheme == "illusory", url.host == "auth",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return false }

        func item(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let provider = item("provider"), let brand = Brand(rawValue: provider) else {
            return false
        }

        if let error = item("error") {
            Log.info("connect: \(provider) failed — \(error)")
            return true
        }

        let expected = UserDefaults.standard.string(forKey: "oauth.state.\(provider)")
        guard let state = item("state"), state == expected else {
            Log.info("connect: \(provider) state mismatch — ignoring callback")
            return true
        }
        guard let token = item("token"), !token.isEmpty else { return true }

        Keychain.set(token, for: "\(provider).token")
        Keychain.set(item("account") ?? "Connected", for: "\(provider).account")
        UserDefaults.standard.removeObject(forKey: "oauth.state.\(provider)")
        Log.info("connect: \(provider) connected")
        // The settings panel checked its state before the browser handed the token
        // back, so without this it goes on saying "not connected" until reopened.
        NotificationCenter.default.post(name: .illusoryConnectionsChanged, object: nil)
        return true
    }

    static func status(for brand: Brand) async -> ConnectionsModel.Status {
        guard token(for: brand) != nil else { return .disconnected }
        return .connected(Keychain.get("\(brand.rawValue).account") ?? "Connected")
    }

    static func pingOllama() async -> Bool {
        guard let url = URL(string: "\(Settings.ollamaHost)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: request)) != nil
    }
}

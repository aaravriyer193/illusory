import Foundation

/// Reads `.env` from the repo root during development, falling back to the real
/// process environment. Tokens move to the Keychain before the app ships; this
/// exists so Phase 2 work isn't blocked on that.
enum Env {
    private static let values: [String: String] = load()

    static subscript(_ key: String) -> String? {
        let value = values[key] ?? ProcessInfo.processInfo.environment[key]
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func load() -> [String: String] {
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent(".env")
            if let text = try? String(contentsOf: candidate, encoding: .utf8) {
                return parse(text)
            }
            dir.deleteLastPathComponent()
        }
        return [:]
    }

    private static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }
}

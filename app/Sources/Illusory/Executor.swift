import AppKit
import CoreGraphics

/// Synthesises keystrokes so Illusory can put text where the caret already is,
/// rather than going via the clipboard — pasting would clobber whatever the user
/// had copied, which is context they may still need.
enum Typing {
    static func insert(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // CGEvent's unicode buffer is small, so long text goes in chunks.
        for offset in stride(from: 0, to: text.count, by: 16) {
            let start = text.index(text.startIndex, offsetBy: offset)
            let end = text.index(start, offsetBy: min(16, text.count - offset))
            var units = Array(text[start..<end].utf16)

            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source,
                                          virtualKey: 0, keyDown: isDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                event.post(tap: .cghidEventTap)
            }
            usleep(1200)
        }
    }
}

/// Carries out a parsed action. Every path reports what it actually did, because
/// the caption after commit should reflect reality rather than the intention.
enum Executor {
    enum ExecError: LocalizedError {
        case needsAccessibility
        case renameFailed(String)

        var errorDescription: String? {
            switch self {
            case .needsAccessibility: return "Needs Accessibility permission to type."
            case .renameFailed(let why): return "Rename failed: \(why)"
            }
        }
    }

    @MainActor
    static func run(_ action: Action) async throws -> String {
        switch action {
        case .none:
            return Intent.nothing

        case .shell(let command, let cwd):
            let output = try await Shell.run(command, cwd: cwd)
            let firstLine = output.split(separator: "\n").first.map(String.init) ?? ""
            return firstLine.isEmpty ? "Done." : String(firstLine.prefix(90))

        case .rename(let pairs):
            var done = 0
            for pair in pairs {
                let from = URL(fileURLWithPath: pair.from)
                // Renames stay inside the original directory; a "rename" that moves
                // a file elsewhere is a different action with different risk.
                let to = from.deletingLastPathComponent()
                    .appendingPathComponent((pair.to as NSString).lastPathComponent)
                do {
                    try FileManager.default.moveItem(at: from, to: to)
                    done += 1
                } catch {
                    throw ExecError.renameFailed(
                        "\(from.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return "Renamed \(done) file\(done == 1 ? "" : "s")."

        case .type(let text), .replaceSelection(let text):
            guard AX.isTrusted else { throw ExecError.needsAccessibility }
            Typing.insert(text)
            return "Typed \(text.count) characters."

        case .appleScript(let source):
            _ = Scripting.run(source)
            return "Done."
        }
    }
}

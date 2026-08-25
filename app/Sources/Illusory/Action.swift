import Foundation

/// What Illusory will actually do, as opposed to what it says it will do.
///
/// A typed set rather than "let the model emit a shell command for everything":
/// each case can be previewed concretely, checked before it runs, and classified
/// by risk. A single free-form escape hatch can be none of those things.
enum Action {
    case none
    case shell(command: String, cwd: String?)
    case rename([(from: String, to: String)])
    case type(String)
    case replaceSelection(String)
    case appleScript(String)

    /// High-risk actions are never run from a tap. A tap is a blind commit, and
    /// anything that can delete or send needs the user to have actually looked at
    /// the preview first.
    var isHighRisk: Bool {
        switch self {
        case .shell, .appleScript: return true
        case .none, .rename, .type, .replaceSelection: return false
        }
    }

    /// Shown in the preview. This is the real thing that will run, not a paraphrase —
    /// the preview is worthless if it describes something other than the action.
    var preview: String {
        switch self {
        case .none:
            return ""
        case .shell(let command, let cwd):
            return cwd.map { "in \(($0 as NSString).lastPathComponent): \(command)" } ?? command
        case .rename(let pairs):
            let shown = pairs.prefix(3).map {
                "\(($0.from as NSString).lastPathComponent) → \(($0.to as NSString).lastPathComponent)"
            }.joined(separator: ", ")
            return pairs.count > 3 ? "\(shown), +\(pairs.count - 3) more" : shown
        case .type(let text), .replaceSelection(let text):
            return "\"\(text.prefix(90))\""
        case .appleScript(let source):
            return source.replacingOccurrences(of: "\n", with: " ").prefix(90).description
        }
    }

    static func parse(_ json: [String: Any]) -> Action {
        switch json["tool"] as? String {
        case "shell":
            guard let spec = json["shell"] as? [String: Any],
                  let command = spec["command"] as? String, !command.isEmpty else { return .none }
            return .shell(command: command, cwd: spec["cwd"] as? String)

        case "rename":
            let pairs = (json["rename"] as? [[String: Any]] ?? []).compactMap { item -> (String, String)? in
                guard let from = item["from"] as? String, let to = item["to"] as? String,
                      !from.isEmpty, !to.isEmpty else { return nil }
                return (from, to)
            }
            return pairs.isEmpty ? .none : .rename(pairs.map { (from: $0.0, to: $0.1) })

        case "type":
            guard let text = json["text"] as? String, !text.isEmpty else { return .none }
            return .type(text)

        case "replace_selection":
            guard let text = json["text"] as? String else { return .none }
            return .replaceSelection(text)

        case "applescript":
            guard let source = json["applescript"] as? String, !source.isEmpty else { return .none }
            return .appleScript(source)

        default:
            return .none
        }
    }
}

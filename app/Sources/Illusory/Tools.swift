import AppKit

/// One thing Illusory will do. The model emits a list of these; the agent runs
/// them in order and feeds failures back so it can correct itself.
struct Step {
    let tool: String
    let args: [String: Any]

    func string(_ key: String) -> String? {
        (args[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    func int(_ key: String) -> Int? { (args[key] as? NSNumber)?.intValue }
    func point(_ x: String = "x", _ y: String = "y") -> CGPoint? {
        guard let px = (args[x] as? NSNumber)?.doubleValue,
              let py = (args[y] as? NSNumber)?.doubleValue else { return nil }
        return CGPoint(x: px, y: py)
    }

    /// Irreversible, or capable of running arbitrary code. These never execute from
    /// a blind tap — the user has to have seen the preview.
    var isHighRisk: Bool {
        ["shell", "applescript", "trash", "write_file", "move"].contains(tool)
    }

    /// The literal thing that will happen. Never a paraphrase — a preview that
    /// describes something other than the action is not a preview.
    var preview: String {
        switch tool {
        case "shell":       return "$ \(string("command") ?? "")"
        case "rename":      return "rename → \(string("to") ?? "")"
        case "move":        return "move \(name(string("from"))) → \(string("to") ?? "")"
        case "copy":        return "copy \(name(string("from")))"
        case "trash":       return "trash \(name(string("path")))"
        case "mkdir":       return "new folder \(name(string("path")))"
        case "write_file":  return "write \(name(string("path")))"
        case "read_file":   return "read \(name(string("path")))"
        case "list_dir":    return "list \(name(string("path")))"
        case "type":        return "type \"\(string("text")?.prefix(60) ?? "")\""
        case "key":         return "press \((args["modifiers"] as? [String] ?? []).joined(separator: "+"))\(string("key").map { "+\($0)" } ?? "")"
        case "click", "double_click", "right_click":
            return "\(tool.replacingOccurrences(of: "_", with: " ")) at \(Int(point()?.x ?? 0)),\(Int(point()?.y ?? 0))"
        case "click_element": return "click \(string("label") ?? "")"
        case "move_mouse":  return "move cursor"
        case "drag":        return "drag"
        case "scroll":      return "scroll"
        case "open_app":    return "open \(string("name") ?? "")"
        case "activate_app":return "switch to \(string("name") ?? "")"
        case "open_url":    return "open \(string("url")?.prefix(60) ?? "")"
        case "applescript": return "run script"
        case "set_clipboard": return "copy to clipboard"
        case "notify":      return string("text") ?? ""
        default:            return tool
        }
    }

    private func name(_ path: String?) -> String {
        (path as NSString?)?.lastPathComponent ?? "?"
    }
}

enum ToolError: LocalizedError {
    case missingArgument(String, String)
    case unknownTool(String)
    case needsAccessibility
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let tool, let key): return "\(tool) needs \"\(key)\""
        case .unknownTool(let name): return "No such tool: \(name)"
        case .needsAccessibility: return "Needs Accessibility permission"
        case .failed(let why): return why
        }
    }
}

enum Tools {
    /// Handed to the model verbatim. Kept terse — it is sent on every gesture, and
    /// the latency budget is the product.
    static let catalogue = """
    FILES        rename{path,to} move{from,to} copy{from,to} trash{path}
                 mkdir{path} write_file{path,text} read_file{path} list_dir{path}
    SHELL        shell{command,cwd}
    KEYBOARD     type{text} key{key,modifiers[]}
    MOUSE        click_element{label}  <- ALWAYS prefer this over raw coordinates
                 click{x,y} double_click{x,y} right_click{x,y} move_mouse{x,y}
                 drag{x,y,to_x,to_y} scroll{dx,dy}
    APPS         open_app{name} activate_app{name} open_url{url} applescript{source}
    SYSTEM       set_clipboard{text} notify{text}
    """

    @MainActor
    static func run(_ step: Step) async throws -> String {
        let fm = FileManager.default

        func need(_ key: String) throws -> String {
            guard let value = step.string(key) else {
                throw ToolError.missingArgument(step.tool, key)
            }
            return value
        }
        func needsInput() throws {
            guard AX.isTrusted else { throw ToolError.needsAccessibility }
        }

        switch step.tool {

        // MARK: Files

        case "rename":
            let path = try need("path")
            let to = try need("to")
            let from = URL(fileURLWithPath: path)
            // A rename stays in its directory; moving elsewhere is `move`, which
            // carries different risk and is previewed differently.
            let target = from.deletingLastPathComponent()
                .appendingPathComponent((to as NSString).lastPathComponent)
            try fm.moveItem(at: from, to: target)
            return "Renamed to \(target.lastPathComponent)"

        case "move":
            let from = URL(fileURLWithPath: try need("from"))
            var to = URL(fileURLWithPath: try need("to"))
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: to.path, isDirectory: &isDir), isDir.boolValue {
                to = to.appendingPathComponent(from.lastPathComponent)
            }
            try fm.moveItem(at: from, to: to)
            return "Moved \(from.lastPathComponent)"

        case "copy":
            let from = URL(fileURLWithPath: try need("from"))
            var to = URL(fileURLWithPath: try need("to"))
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: to.path, isDirectory: &isDir), isDir.boolValue {
                to = to.appendingPathComponent(from.lastPathComponent)
            }
            try fm.copyItem(at: from, to: to)
            return "Copied \(from.lastPathComponent)"

        case "trash":
            // Trash, never unlink. Illusory has no undo layer yet, and the Finder's
            // one is the only thing standing between a wrong guess and lost work.
            let url = URL(fileURLWithPath: try need("path"))
            try fm.trashItem(at: url, resultingItemURL: nil)
            return "Moved \(url.lastPathComponent) to Trash"

        case "mkdir":
            let url = URL(fileURLWithPath: try need("path"))
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return "Created \(url.lastPathComponent)"

        case "write_file":
            let url = URL(fileURLWithPath: try need("path"))
            try (step.string("text") ?? "").write(to: url, atomically: true, encoding: .utf8)
            return "Wrote \(url.lastPathComponent)"

        case "read_file":
            let url = URL(fileURLWithPath: try need("path"))
            let text = try String(contentsOf: url, encoding: .utf8)
            return String(text.prefix(2000))

        case "list_dir":
            let url = URL(fileURLWithPath: try need("path"))
            let names = try fm.contentsOfDirectory(atPath: url.path).sorted()
            return names.prefix(80).joined(separator: "\n")

        // MARK: Shell

        case "shell":
            return try await Shell.run(try need("command"), cwd: step.string("cwd"))

        // MARK: Input

        case "type":
            try needsInput()
            Input.type(try need("text"))
            return "Typed"

        case "key":
            try needsInput()
            Input.press(try need("key"), step.args["modifiers"] as? [String] ?? [])
            return "Pressed"

        case "click_element":
            try needsInput()
            let wanted = try need("label")
            guard let front = NSWorkspace.shared.frontmostApplication else {
                throw ToolError.failed("No frontmost app")
            }
            let candidates = AX.clickables(pid: front.processIdentifier)
            let needle = wanted.lowercased()
            // Exact match first, then containment either way — models paraphrase
            // labels ("Save" for "Save URLs") more often than they get them exact.
            let match = candidates.first { $0.label.lowercased() == needle }
                ?? candidates.first { $0.label.lowercased().contains(needle) }
                ?? candidates.first { needle.contains($0.label.lowercased()) }
            guard let match else {
                throw ToolError.failed("No control labelled \"\(wanted)\" — saw: "
                    + candidates.prefix(8).map(\.label).joined(separator: ", "))
            }
            Log.info("click_element '\(wanted)' -> '\(match.label)' at "
                   + "\(Int(match.centre.x)),\(Int(match.centre.y))")
            Input.click(at: match.centre)
            return "Clicked \(match.label)"

        case "click_element":
            try needsInput()
            let wanted = try need("label")
            guard let front = NSWorkspace.shared.frontmostApplication else {
                throw ToolError.failed("No frontmost app")
            }
            let candidates = AX.clickables(pid: front.processIdentifier)
            let needle = wanted.lowercased()
            // Exact match first, then containment either way — models paraphrase
            // labels ("Save" for "Save URLs") more often than they get them exact.
            let match = candidates.first { $0.label.lowercased() == needle }
                ?? candidates.first { $0.label.lowercased().contains(needle) }
                ?? candidates.first { needle.contains($0.label.lowercased()) }
            guard let match else {
                throw ToolError.failed("No control labelled \"\(wanted)\" — saw: "
                    + candidates.prefix(8).map(\.label).joined(separator: ", "))
            }
            Log.info("click_element '\(wanted)' -> '\(match.label)' at "
                   + "\(Int(match.centre.x)),\(Int(match.centre.y))")
            Input.click(at: match.centre)
            return "Clicked \(match.label)"

        case "click", "double_click", "right_click":
            try needsInput()
            guard let at = step.point() else {
                throw ToolError.missingArgument(step.tool, "x/y")
            }
            Input.click(at: Screenshot.toScreen(at),
                        button: step.tool == "right_click" ? .right : .left,
                        count: step.tool == "double_click" ? 2 : 1)
            return "Clicked"

        case "move_mouse":
            try needsInput()
            guard let at = step.point() else {
                throw ToolError.missingArgument(step.tool, "x/y")
            }
            Input.move(to: Screenshot.toScreen(at))
            return "Moved cursor"

        case "drag":
            try needsInput()
            guard let from = step.point(), let to = step.point("to_x", "to_y") else {
                throw ToolError.missingArgument(step.tool, "x/y/to_x/to_y")
            }
            Input.drag(from: Screenshot.toScreen(from), to: Screenshot.toScreen(to))
            return "Dragged"

        case "scroll":
            try needsInput()
            Input.scroll(dx: step.int("dx") ?? 0, dy: step.int("dy") ?? 0)
            return "Scrolled"

        // MARK: Apps

        case "open_app", "activate_app":
            let name = try need("name")
            guard NSWorkspace.shared.launchApplication(name) else {
                throw ToolError.failed("Could not open \(name)")
            }
            return "Opened \(name)"

        case "open_url":
            guard let url = URL(string: try need("url")) else {
                throw ToolError.failed("Not a URL")
            }
            NSWorkspace.shared.open(url)
            return "Opened link"

        case "applescript":
            let source = try need("source")
            guard let result = Scripting.run(source) else { return "Script ran" }
            return String(result.prefix(400))

        // MARK: System

        case "set_clipboard":
            let text = try need("text")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "Copied to clipboard"

        case "notify":
            return try need("text")

        default:
            throw ToolError.unknownTool(step.tool)
        }
    }
}

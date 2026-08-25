import AppKit
import ApplicationServices

/// Everything Illusory can see at the moment the key is pressed.
///
/// Nothing is captured unless the key is pressed, and nothing is persisted — the
/// keypress is the consent gesture. Every field is optional on purpose: missing
/// permissions or an uncooperative app degrade the proposal, they never fail it.
struct ContextSnapshot {
    // Who
    var appName: String = "unknown"
    var bundleID: String = "unknown"

    // Where
    var windowTitle: String?
    var documentPath: String?
    var url: String?

    // What has focus
    var focusRole: String?
    var focusDescription: String?
    var focusValue: String?
    var placeholder: String?
    var selection: String?
    var caretOffset: Int?

    // What's on disk nearby
    var finderFolder: String?
    var finderSelection: [String] = []
    var files: FileActivity.Report?

    // What's in hand
    var clipboard: String?
    var clipboardTypes: [String] = []
    var clipboardFiles: [String] = []

    // What just happened
    var history: String?
    var localTime: String = ""

    var capture: Screenshot.Capture?
    var screenshot: String? { capture?.base64 }

    // MARK: - Capture

    @MainActor
    static func capture() -> ContextSnapshot {
        var snapshot = ContextSnapshot()

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE HH:mm"
        snapshot.localTime = formatter.string(from: Date())

        let front = NSWorkspace.shared.frontmostApplication
        snapshot.appName = front?.localizedName ?? "unknown"
        snapshot.bundleID = front?.bundleIdentifier ?? "unknown"

        snapshot.captureClipboard()
        if AX.isTrusted, let pid = front?.processIdentifier {
            snapshot.captureAccessibility(pid: pid)
        }
        snapshot.captureFiles()
        return snapshot
    }

    private mutating func captureClipboard() {
        let board = NSPasteboard.general
        clipboardTypes = (board.types ?? []).map(\.rawValue)
        clipboard = board.string(forType: .string).map { String($0.prefix(1500)) }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            clipboardFiles = urls.filter(\.isFileURL).map(\.path)
        }
    }

    private mutating func captureAccessibility(pid: pid_t) {
        let axApp = AXUIElementCreateApplication(pid)

        if let window = AX.element(axApp, kAXFocusedWindowAttribute as String) {
            windowTitle = AX.string(window, kAXTitleAttribute as String)
            documentPath = AX.string(window, kAXDocumentAttribute as String)
            // Browsers hang the address off a web area deeper in the tree.
            url = AX.string(window, "AXURL") ?? AX.search(window, for: "AXURL")
        }

        guard let focused = AX.element(axApp, kAXFocusedUIElementAttribute as String) else { return }
        focusRole = AX.string(focused, kAXRoleAttribute as String)
        focusDescription = AX.string(focused, kAXRoleDescriptionAttribute as String)
        placeholder = AX.string(focused, kAXPlaceholderValueAttribute as String)
        selection = AX.string(focused, kAXSelectedTextAttribute as String).map { String($0.prefix(1500)) }

        // The full field value plus the caret position is what makes "finish this
        // sentence" different from "rewrite this field".
        if let value = AX.string(focused, kAXValueAttribute as String) {
            focusValue = String(value.prefix(1500))
        }
        caretOffset = AX.range(focused, kAXSelectedTextRangeAttribute as String)?.location
    }

    private mutating func captureFiles() {
        if bundleID == "com.apple.finder" {
            finderFolder = Scripting.finderFolder()
            finderSelection = Scripting.finderSelection()
        }
        // Prefer the folder the user is looking at, then the document's folder,
        // then wherever on disk something changed most recently.
        let directory = finderFolder
            ?? documentPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        if let directory {
            files = FileActivity.report(for: directory)
        } else {
            files = FileActivity.mostActiveFallback()
        }
    }

    /// Split out so the cheap fields are gathered instantly and the expensive frame
    /// grab is optional.
    @MainActor
    static func full() async -> ContextSnapshot {
        var snapshot = capture()
        snapshot.history = ActivityLog.shared.recent
        snapshot.capture = await Screenshot.capture()
        return snapshot
    }

    // MARK: - Prompt

    var promptDescription: String {
        var blocks: [String] = ["Local time: \(localTime)",
                                "Frontmost app: \(appName) (\(bundleID))"]

        var place: [String] = []
        if let windowTitle { place.append("Window title: \(windowTitle)") }
        if let url { place.append("URL: \(url)") }
        if let documentPath { place.append("Document: \(documentPath)") }
        if !place.isEmpty { blocks.append(place.joined(separator: "\n")) }

        var focus: [String] = []
        if let focusRole { focus.append("Focused element: \(focusRole) \(focusDescription ?? "")") }
        if let placeholder { focus.append("Placeholder: \(placeholder)") }
        if let caretOffset { focus.append("Caret at character \(caretOffset)") }
        if let focusValue { focus.append("Field contents:\n\(focusValue)") }
        if let selection { focus.append("Selected text:\n\(selection)") }
        if !focus.isEmpty { blocks.append(focus.joined(separator: "\n")) }

        if let finderFolder {
            var finder = ["Finder is showing: \(finderFolder)"]
            if !finderSelection.isEmpty {
                finder.append("Selected there:\n" + finderSelection.map { "  \($0)" }.joined(separator: "\n"))
            }
            blocks.append(finder.joined(separator: "\n"))
        }

        if let files { blocks.append(files.description) }

        var board: [String] = []
        if let clipboard { board.append("Clipboard text:\n\(clipboard)") }
        if !clipboardFiles.isEmpty {
            board.append("Clipboard files:\n" + clipboardFiles.map { "  \($0)" }.joined(separator: "\n"))
        }
        if !board.isEmpty { blocks.append(board.joined(separator: "\n")) }

        if let history { blocks.append("Recent activity (newest last):\n\(history)") }
        if let capture {
            // The model must answer in the image's own pixel space; Illusory maps
            // that back onto the display, which is a different size entirely.
            blocks.append("A screenshot of the screen is attached. It is "
                        + "\(capture.width)x\(capture.height) pixels. Any click or "
                        + "drag coordinates you give must be in that pixel space, "
                        + "measured from its top-left corner.")
        }

        return blocks.joined(separator: "\n\n---\n\n")
    }
}

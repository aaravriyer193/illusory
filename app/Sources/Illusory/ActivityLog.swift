import AppKit

/// A short rolling memory of what the user has been doing, so Illusory can infer a
/// pattern rather than judging a single frozen moment — renaming two files only
/// reads as a pattern if the earlier rename is still remembered.
///
/// In-memory ring buffer only. Nothing is persisted, and it holds minutes, not days.
@MainActor
final class ActivityLog {
    static let shared = ActivityLog()

    private struct Event {
        let at: Date
        let text: String
    }

    private var events: [Event] = []
    private let limit = 40
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var clipboardTimer: Timer?
    private var windowTimer: Timer?
    private var lastWindowTitle: String?
    private var lastApp: String?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let name = app?.localizedName else { return }
            Task { @MainActor in ActivityLog.shared.record("switched to \(name)") }
        }

        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in ActivityLog.shared.pollClipboard() }
        }

        // Window titles are how you see navigation and document switches — moving
        // between files in an editor never fires an app-activation notification.
        windowTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in ActivityLog.shared.pollWindow() }
        }
    }

    private func pollWindow() {
        guard AX.isTrusted,
              let front = NSWorkspace.shared.frontmostApplication,
              let name = front.localizedName else { return }
        let axApp = AXUIElementCreateApplication(front.processIdentifier)
        guard let window = AX.element(axApp, kAXFocusedWindowAttribute as String),
              let title = AX.string(window, kAXTitleAttribute as String) else { return }

        guard title != lastWindowTitle || name != lastApp else { return }
        lastWindowTitle = title
        lastApp = name
        record("viewing \"\(title)\" in \(name)")
    }

    private func pollClipboard() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let flat = text.prefix(160).replacingOccurrences(of: "\n", with: " ")
        record("copied: \(flat)")

        // File copies are a far stronger signal than text, so name them explicitly.
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let files = urls.filter(\.isFileURL).map(\.lastPathComponent)
            if !files.isEmpty { record("copied files: \(files.joined(separator: ", "))") }
        }
    }

    func record(_ text: String) {
        events.append(Event(at: Date(), text: text))
        if events.count > limit { events.removeFirst(events.count - limit) }
    }

    /// Formatted newest-last with relative timestamps, which is what makes a
    /// sequence legible as a pattern.
    var recent: String? {
        guard !events.isEmpty else { return nil }
        let now = Date()
        return events.suffix(limit).map { event in
            let ago = Int(now.timeIntervalSince(event.at))
            return "\(ago)s ago: \(event.text)"
        }.joined(separator: "\n")
    }
}

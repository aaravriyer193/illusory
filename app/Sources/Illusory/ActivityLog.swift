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
    private let limit = 24
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var clipboardTimer: Timer?

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
    }

    private func pollClipboard() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        record("copied: \(text.prefix(120).replacingOccurrences(of: "\n", with: " "))")
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

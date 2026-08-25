import AppKit
import ApplicationServices

/// What Illusory can see at the moment the key is pressed. Nothing is captured
/// unless the key is pressed, and nothing is persisted — the keypress is the
/// consent gesture, so this must stay cheap and short-lived.
struct ContextSnapshot {
    var appName: String
    var bundleID: String
    var windowTitle: String?
    var selection: String?
    var clipboard: String?
    var history: String?
    var screenshot: String?

    @MainActor
    static func capture(includeScreenshot: Bool = true) -> ContextSnapshot {
        let front = NSWorkspace.shared.frontmostApplication
        var snapshot = ContextSnapshot(
            appName: front?.localizedName ?? "unknown",
            bundleID: front?.bundleIdentifier ?? "unknown",
            windowTitle: nil,
            selection: nil,
            clipboard: NSPasteboard.general.string(forType: .string).map { String($0.prefix(1200)) },
            history: nil,
            screenshot: nil
        )

        // Window title and selected text need Accessibility. If it hasn't been
        // granted, Illusory works with less context rather than nagging for it.
        guard AXIsProcessTrusted(), let pid = front?.processIdentifier else { return snapshot }
        let axApp = AXUIElementCreateApplication(pid)

        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString,
                                         &focused) == .success,
           let element = focused {
            var selected: CFTypeRef?
            if AXUIElementCopyAttributeValue(element as! AXUIElement,
                                             kAXSelectedTextAttribute as CFString,
                                             &selected) == .success,
               let text = selected as? String, !text.isEmpty {
                snapshot.selection = String(text.prefix(1200))
            }
        }

        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString,
                                         &window) == .success,
           let win = window {
            var title: CFTypeRef?
            if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString,
                                             &title) == .success {
                snapshot.windowTitle = title as? String
            }
        }
        return snapshot
    }

    /// Split from `capture()` so the cheap parts are gathered instantly and the
    /// expensive frame grab is optional.
    @MainActor
    static func full() -> ContextSnapshot {
        var snapshot = capture()
        snapshot.history = ActivityLog.shared.recent
        snapshot.screenshot = Screenshot.captureBase64JPEG()
        return snapshot
    }

    var promptDescription: String {
        var parts = ["Frontmost app: \(appName) (\(bundleID))"]
        if let windowTitle, !windowTitle.isEmpty { parts.append("Window: \(windowTitle)") }
        if let selection { parts.append("Selected text:\n\(selection)") }
        if let clipboard { parts.append("Clipboard:\n\(clipboard)") }
        if let history { parts.append("Recent activity (newest last):\n\(history)") }
        if screenshot != nil { parts.append("A screenshot of the current screen is attached.") }
        return parts.joined(separator: "\n\n")
    }
}

/// Turns a snapshot into the one small step the user was about to take themselves.
enum Intent {
    static let system = """
    You are Illusory. The user pressed one key while working. From the screenshot, \
    their recent activity and the context below, infer the single small step they \
    were about to do themselves and state it in one short imperative sentence, \
    under 12 words.

    Recent activity matters most: two files renamed the same way means finish the \
    rest. Prefer continuing a pattern the user has already started over anything \
    you merely see on screen.

    Hard rule: only propose something that would take a person about thirty seconds. \
    Never propose a project, a multi-step plan, or anything needing clarification. \
    If the context is too thin to be confident, reply exactly: Nothing obvious to finish.

    Reply with the sentence alone. No preamble, no quotes, no explanation.
    """

    static func propose(_ snapshot: ContextSnapshot) async throws -> String {
        try await OpenRouter.complete(system: system,
                                      user: snapshot.promptDescription,
                                      imageBase64JPEG: snapshot.screenshot)
    }
}

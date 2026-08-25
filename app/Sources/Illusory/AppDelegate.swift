import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private let companion = NotchCompanion()
    private var overlay: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        companion.show()

        // Right Option as the gesture key. Hold to preview, release to commit.
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        hotKey?.onPress = { [weak self] in self?.beginGesture() }
        hotKey?.onRelease = { [weak self] in self?.endGesture() }

        Task { await Self.reportConnections() }
    }

    /// Startup connectivity check. Illusory has no sign-in of its own, so this is
    /// only reporting which of *your* workspaces it currently holds a token for.
    private static func reportConnections() async {
        guard Slack.isConfigured else {
            print("Slack: not connected — \(Slack.SlackError.noToken.localizedDescription)")
            return
        }
        do {
            let me = try await Slack.whoAmI()
            print("Slack: connected as \(me.user) in \(me.team)")
        } catch {
            print("Slack: \(error.localizedDescription)")
        }
    }

    /// Held: capture context, infer the next step, and show what will happen.
    /// Nothing is executed until the key comes back up.
    private func beginGesture() {
        companion.setActive(true)
        guard overlay == nil, let screen = NSScreen.main else { return }

        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: SweepOverlay(caption: "Reading what you're doing…"))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        overlay = panel
    }

    /// Released: commit. Anything Illusory does from here is bounded by the one
    /// rule — nothing slower than a second, nothing bigger than thirty seconds
    /// of the user's own work.
    private func endGesture() {
        companion.setActive(false)
        overlay?.orderOut(nil)
        overlay = nil
    }
}

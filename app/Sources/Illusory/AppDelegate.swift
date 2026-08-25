import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private let statusItem = StatusItemController()
    private var overlay: NSPanel?

    private var pressedAt: Date?
    private var holdTimer: Timer?

    /// Under this, the gesture is a tap: Illusory just goes. Over it, the user is
    /// holding to look first, so the preview stays up until they let go.
    private let holdThreshold: TimeInterval = 0.25

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.install()

        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
        hotKey?.onPress = { Task { @MainActor in self.keyDown() } }
        hotKey?.onRelease = { Task { @MainActor in self.keyUp() } }

        Task { await Self.reportConnections() }
    }

    // MARK: - Gesture

    private func keyDown() {
        pressedAt = Date()
        holdTimer?.invalidate()
        // Only paint the preview if they're still holding once the threshold passes,
        // so a quick tap never flashes a half-drawn overlay.
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { _ in
            Task { @MainActor in self.showOverlay(caption: "Reading what you're doing…") }
        }
    }

    private func keyUp() {
        holdTimer?.invalidate()
        let held = Date().timeIntervalSince(pressedAt ?? Date())
        pressedAt = nil

        if held < holdThreshold {
            // Tap: no time to look, so show the sweep just long enough to register
            // that something happened, then commit.
            showOverlay(caption: "Finishing what you started…")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.hideOverlay()
                self.commit()
            }
        } else {
            hideOverlay()
            commit()
        }
    }

    /// Everything Illusory does is bounded by the one rule — nothing slower than a
    /// second, nothing bigger than thirty seconds of the user's own work.
    private func commit() {
        // Executors land here: capture context, infer the next step, run it.
    }

    // MARK: - Overlay

    private func showOverlay(caption: String) {
        statusItem.setActive(true)
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
        panel.contentView = NSHostingView(rootView: SweepOverlay(caption: caption))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        overlay = panel
    }

    private func hideOverlay() {
        statusItem.setActive(false)
        overlay?.orderOut(nil)
        overlay = nil
    }

    // MARK: - Connections

    /// Illusory has no sign-in of its own; this only reports which of *your*
    /// workspaces it currently holds a token for.
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
}

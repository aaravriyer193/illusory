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
    private var watchdog: Timer?
    /// Bumped on every press. Work scheduled by an earlier gesture checks this
    /// before touching the overlay, so a second press can't be torn down by the
    /// first one's pending cleanup.
    private var generation = 0

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
        generation += 1
        let gen = generation
        pressedAt = Date()
        holdTimer?.invalidate()
        // Only paint the preview if they're still holding once the threshold passes,
        // so a quick tap never flashes a half-drawn overlay.
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { _ in
            Task { @MainActor in
                guard self.generation == gen else { return }
                self.showOverlay(caption: "Reading what you're doing…")
            }
        }
    }

    private func keyUp() {
        holdTimer?.invalidate()
        let gen = generation
        let held = Date().timeIntervalSince(pressedAt ?? Date())
        pressedAt = nil

        if held < holdThreshold {
            // Tap: no time to look, so show the sweep just long enough to register
            // that something happened, then commit.
            showOverlay(caption: "Finishing what you started…")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard self.generation == gen else { return }
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

        // Nothing Illusory does may outlive the one-second rule by much. If the
        // overlay is somehow still up after this, it is a bug, not a long task.
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
            Task { @MainActor in
                guard self.overlay != nil else { return }
                Log.info("overlay watchdog fired — forcing it down")
                self.hideOverlay()
            }
        }
    }

    private func hideOverlay() {
        watchdog?.invalidate()
        watchdog = nil
        statusItem.setActive(false)
        overlay?.orderOut(nil)
        overlay = nil
    }

    // MARK: - Connections

    /// Illusory has no sign-in of its own; this only reports which of *your*
    /// workspaces it currently holds a token for.
    private static func reportConnections() async {
        guard Slack.isConfigured else {
            Log.info("Slack: not connected — \(Slack.SlackError.noToken.localizedDescription)")
            return
        }
        do {
            let me = try await Slack.whoAmI()
            Log.info("Slack: connected as \(me.user) in \(me.team)")
        } catch {
            Log.info("Slack: \(error.localizedDescription)")
        }
    }
}

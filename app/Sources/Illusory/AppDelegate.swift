import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private let statusItem = StatusItemController()
    private var overlay: NSPanel?
    private let gesture = GestureState()

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
        ActivityLog.shared.start()

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
            commit(generation: gen)
        } else {
            commit(generation: gen)
        }
    }

    /// Everything Illusory does is bounded by the one rule — nothing slower than a
    /// second, nothing bigger than thirty seconds of the user's own work.
    private func commit(generation gen: Int) {
        guard OpenRouter.isConfigured else {
            Log.info("OpenRouter: no key set")
            showOverlay(caption: "No model configured.")
            dismiss(after: .milliseconds(1400), generation: gen)
            return
        }

        let snapshot = ContextSnapshot.full()
        Log.info("context: \(snapshot.appName) · selection=\(snapshot.selection != nil)"
               + " · clipboard=\(snapshot.clipboard != nil) · shot=\(snapshot.screenshot != nil)"
               + " · history=\(snapshot.history != nil)")
        showOverlay(caption: "Thinking…")

        Task { @MainActor in
            let started = Date()
            do {
                let proposal = try await Intent.propose(snapshot)
                guard self.generation == gen else { return }
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                Log.info("proposed in \(elapsed)ms: \(proposal)")
                self.gesture.caption = proposal
            } catch {
                guard self.generation == gen else { return }
                Log.info("model error: \(error.localizedDescription)")
                self.gesture.caption = error.localizedDescription
            }
            self.dismiss(after: .milliseconds(2000), generation: gen)
        }
    }

    private func dismiss(after delay: Duration, generation gen: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard self.generation == gen else { return }
            self.hideOverlay()
        }
    }

    // MARK: - Overlay

    private func showOverlay(caption: String) {
        gesture.caption = caption
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
        panel.contentView = NSHostingView(rootView: SweepOverlay(state: gesture))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        overlay = panel

        // Nothing Illusory does may outlive the one-second rule by much. If the
        // overlay is somehow still up after this, it is a bug, not a long task.
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in
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
        guard Integrations.enabled else {
            Log.info("integrations: off")
            return
        }
        guard Slack.isConfigured else {
            Log.info("Slack: no token")
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

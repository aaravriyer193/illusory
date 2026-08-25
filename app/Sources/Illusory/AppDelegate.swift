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
    private var thinking: Task<Void, Never>?
    private var pendingProposal: Intent.Proposal?
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

        // Most of the context — window titles, focused field, selected text — needs
        // Accessibility. Ask once at launch rather than failing quietly per gesture.
        if !AX.isTrusted {
            Log.info("accessibility: not trusted, prompting")
            AX.requestTrust()
        }

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

        // Thinking starts on the way down, not on release. During a hold this runs
        // underneath the user's own delay, so the preview is often ready by the time
        // they have finished deciding to look at it.
        startThinking(generation: gen)

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

        showOverlay(caption: gesture.caption.isEmpty ? "Thinking…" : gesture.caption)
        commit(generation: gen, wasTap: held < holdThreshold)
    }

    /// Works out what to do, and shows it. Nothing is carried out here — the user
    /// is still holding the key, and the preview is the point of the hold.
    private func startThinking(generation gen: Int) {
        pendingProposal = nil
        thinking?.cancel()

        guard OpenRouter.isConfigured else {
            Log.info("OpenRouter: no key set")
            gesture.caption = "No model configured."
            return
        }

        gesture.caption = "Reading what you're doing…"
        thinking = Task { @MainActor in
            let started = Date()
            let snapshot = await ContextSnapshot.full()
            Log.info("context: \(snapshot.appName) · selection=\(snapshot.selection != nil)"
                   + " · clipboard=\(snapshot.clipboard != nil)"
                   + " · shot=\(snapshot.screenshot != nil)"
                   + " · history=\(snapshot.history != nil)"
                   + " · files=\(snapshot.files != nil)")
            guard self.generation == gen, !Task.isCancelled else { return }

            do {
                let proposal = try await Intent.propose(snapshot)
                guard self.generation == gen, !Task.isCancelled else { return }
                Log.info("proposed in \(Int(Date().timeIntervalSince(started) * 1000))ms "
                       + "[conf \(proposal.confidence), basis: \(proposal.basis)] "
                       + "\(proposal.summary) :: \(proposal.action.preview)")
                self.pendingProposal = proposal
                // Below the bar Illusory says nothing rather than inventing a step.
                self.gesture.caption = proposal.isActionable
                    ? proposal.previewCaption : Intent.nothing
            } catch {
                guard self.generation == gen else { return }
                Log.info("model error: \(error.localizedDescription)")
                self.gesture.caption = error.localizedDescription
            }
        }
    }

    /// Release commits. Everything Illusory carries out is bounded by the one rule —
    /// nothing slower than a second, nothing bigger than thirty seconds of the
    /// user's own work.
    private func commit(generation gen: Int, wasTap: Bool) {
        Task { @MainActor in
            _ = await thinking?.result
            guard self.generation == gen else { return }

            guard let proposal = self.pendingProposal, proposal.isActionable else {
                self.dismiss(after: .milliseconds(1600), generation: gen)
                return
            }

            // A tap is a blind commit — the user never saw the preview. Anything
            // that can delete, send, or run arbitrary code needs to have been
            // looked at first, so a tap shows it and waits for a deliberate hold.
            if wasTap, proposal.action.isHighRisk {
                Log.info("tap on high-risk action — holding for confirmation")
                self.gesture.caption = "Hold ⌥Space to run:\n\(proposal.action.preview)"
                self.dismiss(after: .milliseconds(2600), generation: gen)
                return
            }

            self.gesture.caption = "Doing it…"
            do {
                let result = try await Executor.run(proposal.action)
                guard self.generation == gen else { return }
                Log.info("executed: \(result)")
                self.gesture.caption = result
            } catch {
                guard self.generation == gen else { return }
                Log.info("execution failed: \(error.localizedDescription)")
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

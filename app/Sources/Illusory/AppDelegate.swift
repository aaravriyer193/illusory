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
    /// The run in progress, held so the stop button can cancel it.
    private var running: Task<Void, Never>?
    private var pendingPlan: Agent.Plan?
    private var pendingContext: ContextSnapshot?
    /// Bumped on every press. Work scheduled by an earlier gesture checks this
    /// before touching the overlay, so a second press can't be torn down by the
    /// first one's pending cleanup.
    private var generation = 0

    /// Under this, the gesture is a tap: Illusory just goes. Over it, the user is
    /// holding to look first, so the preview stays up until they let go.
    private var holdThreshold: TimeInterval { Settings.holdThreshold }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.install()
        statusItem.onStop = { [weak self] in self?.stopNow() }
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

        // Tokens come back from the website through the URL scheme.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        Log.info("ready · provider \(Settings.provider.rawValue) · model \(Settings.model)")
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor,
                                      reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        Connect.handle(url)
    }

    /// Cancels whatever is running and clears the screen immediately. Input
    /// already posted cannot be recalled, but nothing further is sent.
    private func stopNow() {
        generation += 1
        thinking?.cancel()
        running?.cancel()
        thinking = nil
        running = nil
        gesture.caption = "Stopped."
        let gen = generation
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard self.generation == gen else { return }
            self.hideOverlay()
        }
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
        pendingPlan = nil
        pendingContext = nil
        thinking?.cancel()

        guard Model.isConfigured else {
            Log.info("model: not configured")
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
                   + " · files=\(snapshot.files != nil)"
                   + " · controls=\(snapshot.clickables.count)")
            guard self.generation == gen, !Task.isCancelled else { return }
            self.pendingContext = snapshot

            do {
                let plan = try await Agent.plan(snapshot)
                guard self.generation == gen, !Task.isCancelled else { return }
                Log.info("planned in \(Int(Date().timeIntervalSince(started) * 1000))ms "
                       + "[conf \(plan.confidence), basis: \(plan.basis)] \(plan.summary) "
                       + ":: \(plan.steps.map(\.preview).joined(separator: " | "))")
                self.pendingPlan = plan
                // Below the bar Illusory says nothing rather than inventing a step.
                self.gesture.caption = plan.isActionable ? plan.previewCaption : Agent.nothing
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
        running = Task { @MainActor in
            _ = await thinking?.result
            guard self.generation == gen else { return }

            guard let plan = self.pendingPlan, plan.isActionable else {
                self.dismiss(after: .milliseconds(1600), generation: gen)
                return
            }

            // A tap is a blind commit — the user never saw the preview. Anything
            // that can delete, send, or run arbitrary code needs to have been
            // looked at first, so a tap shows it and waits for a deliberate hold.
            if wasTap, plan.isHighRisk {
                Log.info("tap on high-risk plan — holding for confirmation")
                self.gesture.caption = "Hold ⌥Space to run:\n"
                    + plan.steps.map(\.preview).joined(separator: " · ")
                self.dismiss(after: .milliseconds(2800), generation: gen)
                return
            }

            let snapshot = self.pendingContext ?? ContextSnapshot.capture()
            let result = await Agent.execute(plan, context: snapshot) { progress in
                guard self.generation == gen else { return }
                self.gesture.caption = progress
            }
            guard self.generation == gen else { return }
            Log.info("finished: \(result)")
            self.gesture.caption = result
            self.dismiss(after: .milliseconds(2200), generation: gen)
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
        watchdog = Timer.scheduledTimer(withTimeInterval: Agent.deadline + 30,
                                        repeats: false) { _ in
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

}

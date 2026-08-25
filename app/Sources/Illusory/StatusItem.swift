import AppKit
import SwiftUI

/// Illusory's only permanent presence: a menu-bar status item, in the same strip
/// as every other agent app.
///
/// While a gesture is running it stops being a menu and becomes a stop button.
/// Anything that can type and click on your behalf needs a way to be interrupted
/// that is always in the same place and always one click away — burying that in a
/// menu would mean opening the menu while the thing you want to stop is still
/// typing into it.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var spinTimer: Timer?
    private var angle: CGFloat = 0
    private var menu: NSMenu?

    /// Called when the user clicks the item mid-run.
    var onStop: () -> Void = {}

    private var settingsWindow: NSWindow?

    func install() {
        item.button?.image = Self.markImage(rotation: 0)
        item.button?.toolTip = "Illusory — tap or hold ⌥Space"

        let menu = NSMenu()
        let hint = NSMenuItem(title: "Tap or hold ⌥Space", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let connections = NSMenuItem(title: "Connections & Settings…",
                                     action: #selector(openSettings), keyEquivalent: ",")
        connections.target = self
        menu.addItem(connections)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Illusory",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        self.menu = menu
        item.menu = menu
    }

    func setActive(_ active: Bool) {
        spinTimer?.invalidate()

        guard active else {
            angle = 0
            item.menu = menu
            item.button?.target = nil
            item.button?.action = nil
            item.button?.image = Self.markImage(rotation: 0)
            item.button?.toolTip = "Illusory — tap or hold ⌥Space"
            return
        }

        // Detach the menu so a single click stops the run rather than opening it.
        item.menu = nil
        item.button?.target = self
        item.button?.action = #selector(stopClicked)
        item.button?.toolTip = "Illusory is working — click to stop"

        spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.angle += 4
                self.item.button?.image = Self.markImage(rotation: self.angle, stopping: true)
            }
        }
    }

    @objc private func stopClicked() {
        Log.info("stop: cancelled from the menu bar")
        onStop()
    }

    /// Rendered as a template image so macOS tints it for the light or dark menu bar
    /// automatically, the same way every other status item behaves.
    private static func markImage(rotation: CGFloat, stopping: Bool = false) -> NSImage? {
        let side: CGFloat = 18
        let view = ZStack {
            IllusoryMark(spokes: 28)
                .stroke(Color.black,
                        lineWidth: IllusoryMark.lineWidth(design: 12, renderedAt: side))
                .rotationEffect(.degrees(rotation))
            if stopping {
                // A stop square sitting in the aperture: unmistakable at 18pt, and
                // it reads as "press this" rather than as a progress indicator.
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(Color.black)
                    .frame(width: side * 0.3, height: side * 0.3)
            }
        }
        .frame(width: side, height: side)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = true
        return image
    }

    /// The app is an agent, so it has to explicitly activate to bring a window
    /// forward — otherwise the panel opens behind whatever the user was doing.
    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: ConnectionsView())
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

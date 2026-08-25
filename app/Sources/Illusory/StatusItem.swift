import AppKit
import SwiftUI

/// Illusory's only permanent presence: a menu-bar status item, sitting in the same
/// right-hand strip as every other agent app. It shows the mark at rest and spins
/// it while a gesture is running.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var spinTimer: Timer?
    private var angle: CGFloat = 0

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
        item.menu = menu
    }

    /// The app is an agent, so it has to explicitly activate to bring a window
    /// forward — otherwise the panel opens behind whatever the user was doing.
    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
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

    func setActive(_ active: Bool) {
        spinTimer?.invalidate()
        guard active else {
            angle = 0
            item.button?.image = Self.markImage(rotation: 0)
            return
        }
        spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.angle += 4
                self.item.button?.image = Self.markImage(rotation: self.angle)
            }
        }
    }

    /// Rendered as a template image so macOS tints it for the light or dark menu bar
    /// automatically, the same way every other status item behaves.
    private static func markImage(rotation: CGFloat) -> NSImage? {
        let side: CGFloat = 18
        let view = IllusoryMark(spokes: 28)
            .stroke(Color.black,
                    lineWidth: IllusoryMark.lineWidth(design: 12, renderedAt: side))
            .rotationEffect(.degrees(rotation))
            .frame(width: side, height: side)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = true
        return image
    }
}

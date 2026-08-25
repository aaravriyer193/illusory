import AppKit
import SwiftUI

/// Illusory's only permanent presence: a menu-bar status item, sitting in the same
/// right-hand strip as every other agent app. It shows the mark at rest and spins
/// it while a gesture is running.
@MainActor
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var spinTimer: Timer?
    private var angle: CGFloat = 0

    func install() {
        item.button?.image = Self.markImage(rotation: 0)
        item.button?.toolTip = "Illusory — tap or hold ⌥Space"

        let menu = NSMenu()
        let status = NSMenuItem(title: "Tap or hold ⌥Space", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Illusory",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
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

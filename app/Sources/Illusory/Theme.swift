import SwiftUI
import AppKit

enum Theme {
    /// Geist at weight 350 — set through the variable font's `wght` axis, so it is
    /// the real 350 and not Light rounded up. Falls back to the system face until
    /// the Geist variable font is dropped into Resources/.
    static func geist(_ size: CGFloat) -> Font {
        guard let base = NSFont(name: "Geist", size: size) else {
            return .system(size: size, weight: .light)
        }
        let wght = FourCharCode(0x77676874)  // 'wght'
        let descriptor = base.fontDescriptor.addingAttributes([
            .variation: [wght: 350]
        ])
        return Font(NSFont(descriptor: descriptor, size: size) ?? base)
    }

    /// The sweep's iridescence. Deliberately restrained — the mark is monochrome,
    /// so colour only ever appears while the gesture is live.
    static let sheen: [Color] = [
        Color(red: 0.45, green: 0.55, blue: 1.00),
        Color(red: 0.78, green: 0.52, blue: 0.98),
        Color(red: 0.98, green: 0.56, blue: 0.72),
        Color(red: 0.55, green: 0.82, blue: 0.98),
        Color(red: 0.45, green: 0.55, blue: 1.00),
    ]
}

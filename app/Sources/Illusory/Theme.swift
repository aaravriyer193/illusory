import SwiftUI
import AppKit

enum Theme {
    /// Headings sit at 350 and body text at 400, set through Geist's `wght`
    /// variable axis so these are the real weights rather than Light and Regular
    /// rounded to the nearest named face. Falls back to the system face until the
    /// Geist variable font is dropped into Resources/.
    static func heading(_ size: CGFloat) -> Font { geist(size, weight: 350) }
    static func body(_ size: CGFloat) -> Font { geist(size, weight: 400) }

    private static func geist(_ size: CGFloat, weight: Int) -> Font {
        guard let base = NSFont(name: "Geist", size: size) else {
            return .system(size: size, weight: weight <= 350 ? .light : .regular)
        }
        let wght = FourCharCode(0x77676874)  // 'wght'
        let descriptor = base.fontDescriptor.addingAttributes([.variation: [wght: weight]])
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

import SwiftUI

/// The mark, drawn from the same vesica formula as assets/logo_gen.py so the app
/// and the site never drift apart. Spokes run inward from the rim and stop at the
/// aperture; `twist` offsets each inner endpoint, producing the two bright flares.
struct IllusoryMark: Shape {
    var spokes: Int = 130
    var lensW: CGFloat = 120
    var lensH: CGFloat = 280
    var twist: CGFloat = 25
    private let design: CGFloat = 560
    private let rim: CGFloat = 250

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / design
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = lensW / 2, h = lensH / 2
        let Rl = (w + h * h / w) / 2
        let d = (h * h / w - w) / 2
        let tw = twist * .pi / 180

        func lensRadius(_ p: CGFloat) -> CGFloat {
            let disc = d * d * pow(cos(p), 2) - d * d + Rl * Rl
            return -d * abs(cos(p)) + sqrt(max(disc, 0))
        }

        var path = Path()
        for i in 0..<spokes {
            let t = 2 * .pi * CGFloat(i) / CGFloat(spokes)
            let p = t + tw
            let rl = lensRadius(p)
            path.move(to: CGPoint(x: c.x + rim * cos(t) * scale,
                                  y: c.y + rim * sin(t) * scale))
            path.addLine(to: CGPoint(x: c.x + rl * cos(p) * scale,
                                     y: c.y + rl * sin(p) * scale))
        }
        return path
    }
}

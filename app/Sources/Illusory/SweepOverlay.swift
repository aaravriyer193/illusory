import SwiftUI

/// The screen-scale version of the mark: spokes anchored to the display's edge,
/// running inward, with a flare travelling around the rim exactly like the twist
/// in the logo. Monochrome at rest, iridescent only while a gesture is live.
struct BrandSweep: Shape {
    var spokes: Int = 200
    /// Where the flare currently sits, 0...1 around the rim.
    var phase: CGFloat = 0
    var baseLength: CGFloat = 26
    var flareLength: CGFloat = 92

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        for i in 0..<spokes {
            let f = CGFloat(i) / CGFloat(spokes)
            let t = f * 2 * .pi

            // Distance from centre to the screen edge along this ray, so the spokes
            // hug the rectangle rather than an inscribed circle.
            let dx = abs(cos(t)) < 1e-6 ? .infinity : rect.width / 2 / abs(cos(t))
            let dy = abs(sin(t)) < 1e-6 ? .infinity : rect.height / 2 / abs(sin(t))
            let edge = min(dx, dy)

            // Angular distance to the flare, wrapped, shaped into a soft lobe.
            var delta = abs(f - phase)
            if delta > 0.5 { delta = 1 - delta }
            let lobe = exp(-pow(delta / 0.13, 2))
            let length = baseLength + flareLength * lobe

            let outer = CGPoint(x: c.x + edge * cos(t), y: c.y + edge * sin(t))
            let inner = CGPoint(x: c.x + (edge - length) * cos(t),
                                y: c.y + (edge - length) * sin(t))
            path.move(to: outer)
            path.addLine(to: inner)
        }
        return path
    }
}

/// Shown while the gesture runs. It is not decoration: it is the window in which
/// Illusory says what it is about to do, and the user can still abort.
struct SweepOverlay: View {
    @State private var phase: CGFloat = 0
    @State private var bloom: Double = 0
    var caption: String

    var body: some View {
        ZStack {
            BrandSweep(phase: phase)
                .stroke(
                    AngularGradient(colors: Theme.sheen, center: .center,
                                    angle: .degrees(Double(phase) * 360)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .blur(radius: 0.6)
                .opacity(bloom)

            BrandSweep(phase: phase, baseLength: 18, flareLength: 74)
                .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .blur(radius: 13)
                .opacity(bloom * 0.85)

            VStack {
                Spacer()
                Text(caption)
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                    .padding(.bottom, 66)
                    .opacity(bloom)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                phase = 1
            }
            withAnimation(.easeOut(duration: 0.24)) { bloom = 1 }
        }
    }
}

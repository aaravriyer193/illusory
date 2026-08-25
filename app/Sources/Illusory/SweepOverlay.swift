import SwiftUI

/// The full-screen edge glow shown while the hotkey is held. It is not decoration:
/// it is the window during which Illusory shows what it is about to do, and the
/// user can still abort. One second, start to finish.
struct SweepOverlay: View {
    @State private var phase: Double = 0
    @State private var bloom: Double = 0
    var caption: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: Theme.sheen, center: .center,
                                    angle: .degrees(phase)),
                    lineWidth: 16
                )
                .blur(radius: 22)
                .opacity(bloom)

            VStack {
                Spacer()
                Text(caption)
                    .font(Theme.geist(15))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 64)
                    .opacity(bloom)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 360
            }
            withAnimation(.easeOut(duration: 0.28)) { bloom = 1 }
        }
    }
}

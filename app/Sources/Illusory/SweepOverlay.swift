import SwiftUI

/// Live text for the overlay, so the caption can move from "reading" to "thinking"
/// to the proposed action without tearing the window down and rebuilding it.
@MainActor
final class GestureState: ObservableObject {
    @Published var caption: String = ""
}

/// Shown while the gesture runs. It is not decoration: it is the window in which
/// Illusory says what it is about to do, and the user can still abort.
struct SweepOverlay: View {
    @ObservedObject var state: GestureState
    @State private var phase: Double = 0
    @State private var bloom: Double = 0

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

            VStack(spacing: 9) {
                Spacer()
                Text(state.caption)
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.94))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    // Background before the frame, so the capsule hugs its text and
                    // the frame only centres it — otherwise it stretches to the cap.
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                    .frame(maxWidth: 640)
                    .opacity(bloom)
                    .animation(.easeInOut(duration: 0.18), value: state.caption)

                Text("click the mark in the menu bar to stop")
                    .font(Theme.body(11))
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(bloom)
                    .padding(.bottom, 130)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 360
            }
            withAnimation(.easeOut(duration: 0.24)) { bloom = 1 }
        }
    }
}

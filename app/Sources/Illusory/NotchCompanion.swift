import SwiftUI
import AppKit

/// Illusory's only permanent presence: a small panel tucked into the menu-bar strip
/// beside the notch. It shows the mark at rest and pulses while a gesture runs.
/// On machines without a notch it sits at the same place the notch would occupy.
final class NotchCompanion {
    private var panel: NSPanel?
    private let state = CompanionState()

    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }
        let size = NSSize(width: 34, height: 22)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CompanionView(state: state))

        // Prefer the strip to the right of the notch; fall back to the menu bar.
        let frame = screen.frame
        let menuBarTop = frame.maxY - 1
        let x: CGFloat
        if let aux = screen.auxiliaryTopRightArea {
            x = aux.minX + 8
        } else {
            x = frame.midX + 120
        }
        panel.setFrameOrigin(NSPoint(x: x, y: menuBarTop - size.height - 1))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func setActive(_ active: Bool) { state.active = active }
}

final class CompanionState: ObservableObject {
    @Published var active = false
}

private struct CompanionView: View {
    @ObservedObject var state: CompanionState
    @State private var spin: Double = 0

    var body: some View {
        IllusoryMark(spokes: 28)
            .stroke(state.active ? AnyShapeStyle(AngularGradient(colors: Theme.sheen,
                                                                center: .center))
                                 : AnyShapeStyle(Color.primary.opacity(0.62)),
                    lineWidth: IllusoryMark.lineWidth(design: 12, renderedAt: 18))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(spin))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: state.active) { _, isActive in
                if isActive {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        spin += 360
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) { spin = 0 }
                }
            }
    }
}

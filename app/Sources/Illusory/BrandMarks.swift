import SwiftUI

/// Simplified marks for the services Illusory connects to.
///
/// Drawn rather than bundled as image assets: they have to read at 16pt in a
/// caption pill, where full brand artwork turns to mush, and drawing them keeps
/// them sharp at any size and tintable when they need to be monochrome.
enum Brand: String, CaseIterable, Identifiable {
    case slack, notion, github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slack:  return "Slack"
        case .notion: return "Notion"
        case .github: return "GitHub"
        }
    }
}

struct BrandMark: View {
    let brand: Brand
    var size: CGFloat = 16
    /// Greyed when the service isn't connected, so the panel reads at a glance.
    var active: Bool = true

    var body: some View {
        Group {
            switch brand {
            case .slack:  slack
            case .notion: notion
            case .github: github
            }
        }
        .frame(width: size, height: size)
        .saturation(active ? 1 : 0)
        .opacity(active ? 1 : 0.45)
    }

    // Four rounded bars in a pinwheel — the part of the Slack mark that survives
    // being shrunk.
    private var slack: some View {
        GeometryReader { geo in
            let s = geo.size.width
            let thickness = s * 0.26
            let length = s * 0.62
            let inset = s * 0.06
            ZStack {
                bar(width: length, height: thickness, color: Color(red: 0.13, green: 0.72, blue: 0.49))
                    .offset(x: s * 0.13, y: -s * 0.19 + inset)
                bar(width: length, height: thickness, color: Color(red: 0.88, green: 0.12, blue: 0.35))
                    .offset(x: -s * 0.13, y: s * 0.19 - inset)
                bar(width: thickness, height: length, color: Color(red: 0.21, green: 0.77, blue: 0.94))
                    .offset(x: -s * 0.19 + inset, y: -s * 0.13)
                bar(width: thickness, height: length, color: Color(red: 0.93, green: 0.70, blue: 0.18))
                    .offset(x: s * 0.19 - inset, y: s * 0.13)
            }
            .frame(width: s, height: s)
        }
    }

    private func bar(width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: min(width, height) / 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
    }

    // Notion's rounded page with its angular N.
    private var notion: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.16, style: .continuous)
                    .stroke(Color.primary, lineWidth: s * 0.09)
                Path { path in
                    let left = s * 0.34, right = s * 0.66
                    let top = s * 0.3, bottom = s * 0.7
                    path.move(to: CGPoint(x: left, y: bottom))
                    path.addLine(to: CGPoint(x: left, y: top))
                    path.addLine(to: CGPoint(x: right, y: bottom))
                    path.addLine(to: CGPoint(x: right, y: top))
                }
                .stroke(Color.primary, style: StrokeStyle(lineWidth: s * 0.09,
                                                          lineCap: .round, lineJoin: .round))
            }
            .frame(width: s, height: s)
        }
    }

    // A filled circle with the tail — enough of the Octocat to be unmistakable
    // once you know what you're looking at, and legible at 16pt where the real
    // silhouette is not.
    private var github: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                Circle().fill(Color.primary)
                HStack(spacing: s * 0.14) {
                    Capsule().fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: s * 0.09, height: s * 0.16)
                    Capsule().fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: s * 0.09, height: s * 0.16)
                }
                .offset(y: -s * 0.07)
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: s * 0.1, height: s * 0.26)
                    .offset(y: s * 0.24)
            }
            .frame(width: s, height: s)
        }
    }
}

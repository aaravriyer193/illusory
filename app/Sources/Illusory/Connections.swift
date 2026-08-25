import SwiftUI

/// Live state of the services Illusory holds tokens for. Illusory itself has no
/// account, so "connected" here only ever means *your* workspace, on this machine.
@MainActor
final class ConnectionsModel: ObservableObject {
    enum Status: Equatable {
        case checking
        case comingSoon
        case connected(String)
        case missing(String)
        case failed(String)
    }

    @Published var slack: Status = .checking
    @Published var notion: Status = .checking
    @Published var github: Status = .checking

    func refresh() async {
        guard Integrations.enabled else {
            slack = .comingSoon
            notion = .comingSoon
            github = .comingSoon
            return
        }
        slack = .checking
        if Slack.isConfigured {
            do {
                let me = try await Slack.whoAmI()
                let kind = Env["SLACK_USER_TOKEN"] != nil ? "as you" : "as a bot"
                slack = .connected("\(me.user) · \(me.team) · \(kind)")
            } catch {
                slack = .failed(error.localizedDescription)
            }
        } else {
            slack = .missing("Install your Slack app, then add the token to .env")
        }

        notion = Env["NOTION_INTERNAL_TOKEN"] != nil || Env["NOTION_CLIENT_ID"] != nil
            ? .connected("Token present")
            : .missing("Not set up yet")

        github = Env["GITHUB_CLIENT_ID"] != nil
            ? .connected("Client configured")
            : .missing("Not set up yet")
    }
}

struct ConnectionsView: View {
    @StateObject private var model = ConnectionsModel()
    @State private var holdThreshold: Double = 0.25

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header

            section("Connections") {
                row("Slack", model.slack)
                row("Notion", model.notion)
                row("GitHub", model.github)
            }

            section("Gesture") {
                LabeledContent {
                    Text("⌥Space").font(Theme.body(12)).foregroundStyle(.secondary)
                } label: {
                    Text("Key").font(Theme.heading(13))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Hold to preview after \(Int(holdThreshold * 1000))ms")
                        .font(Theme.body(13))
                    Slider(value: $holdThreshold, in: 0.1...0.6)
                    Text("Below this, a tap just runs.")
                        .font(Theme.body(11)).foregroundStyle(.tertiary)
                }
            }

            Text("Illusory has no account. Nothing here leaves this Mac.")
                .font(Theme.body(11))
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(width: 400, alignment: .leading)
        .task { await model.refresh() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            IllusoryMark(spokes: 28)
                .stroke(.primary, lineWidth: IllusoryMark.lineWidth(design: 12, renderedAt: 26))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Illusory").font(Theme.heading(16))
                Text("One key. AI finishes what you started.")
                    .font(Theme.body(11)).foregroundStyle(.secondary)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title.uppercased())
                .font(Theme.heading(10)).kerning(0.8).foregroundStyle(.tertiary)
            content()
        }
    }

    private func row(_ name: String, _ status: ConnectionsModel.Status) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Circle().fill(color(for: status)).frame(width: 6, height: 6).offset(y: -1)
            Text(name).font(Theme.heading(13)).frame(width: 60, alignment: .leading)
            Text(detail(for: status))
                .font(Theme.body(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func color(for status: ConnectionsModel.Status) -> Color {
        switch status {
        case .checking, .comingSoon: return .secondary.opacity(0.25)
        case .connected: return .green
        case .missing: return .secondary.opacity(0.4)
        case .failed: return .orange
        }
    }

    private func detail(for status: ConnectionsModel.Status) -> String {
        switch status {
        case .checking: return "Checking…"
        case .comingSoon: return "Coming soon"
        case .connected(let s), .missing(let s), .failed(let s): return s
        }
    }
}

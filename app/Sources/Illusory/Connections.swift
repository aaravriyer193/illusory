import SwiftUI

/// Live state of the services Illusory can act through. Illusory itself has no
/// account, so "connected" here only ever means *your* workspace, on this machine.
@MainActor
final class ConnectionsModel: ObservableObject {
    enum Status: Equatable {
        case comingSoon
        case checking
        case connected(String)
        case disconnected
        case failed(String)

        var isConnected: Bool { if case .connected = self { return true }; return false }
    }

    @Published var status: [Brand: Status] = [:]
    @Published var ollamaReachable: Bool?

    func refresh() async {
        for brand in Brand.allCases {
            status[brand] = Integrations.enabled ? .checking : .comingSoon
        }

        if Integrations.enabled {
            for brand in Brand.allCases {
                status[brand] = await Connect.status(for: brand)
            }
        }

        if Settings.provider == .ollama {
            ollamaReachable = await Connect.pingOllama()
        } else {
            ollamaReachable = nil
        }
    }
}

struct ConnectionsView: View {
    @StateObject private var model = ConnectionsModel()
    @State private var provider = Settings.provider
    @State private var modelName = Settings.model
    @State private var ollamaHost = Settings.ollamaHost
    @State private var holdThreshold = Settings.holdThreshold

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                modelSection
                connectionsSection
                gestureSection

                Text("Illusory has no account. Nothing here leaves this Mac except the "
                   + "model call, and with Ollama not even that.")
                    .font(Theme.body(11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(30)
        }
        .frame(width: 420)
        .task { await model.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            IllusoryMark(spokes: 28)
                .stroke(.primary, lineWidth: IllusoryMark.lineWidth(design: 12, renderedAt: 26))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Illusory").font(Theme.heading(16))
                Text("Autocomplete for everything that isn't typing.")
                    .font(Theme.body(11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        section("Model") {
            Picker("", selection: $provider) {
                ForEach(Provider.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: provider) { _, new in
                Settings.provider = new
                modelName = Settings.model
                Task { await model.refresh() }
            }

            Text(provider.detail)
                .font(Theme.body(11)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if provider == .ollama {
                // Local models are the user's own install, so which one runs is
                // genuinely theirs to pick. The hosted model is not.
                LabeledContent {
                    TextField("", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.body(12))
                        .onSubmit { Settings.model = modelName }
                } label: {
                    Text("Model").font(Theme.heading(13))
                }

                LabeledContent {
                    TextField("", text: $ollamaHost)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.body(12))
                        .onSubmit { Settings.ollamaHost = ollamaHost }
                } label: {
                    Text("Host").font(Theme.heading(13))
                }

                if let reachable = model.ollamaReachable {
                    HStack(spacing: 7) {
                        Circle().fill(reachable ? .green : .orange).frame(width: 6, height: 6)
                        Text(reachable ? "Ollama is running"
                                       : "Can't reach Ollama — is `ollama serve` up?")
                            .font(Theme.body(11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Connections

    private var connectionsSection: some View {
        section("Connections") {
            ForEach(Brand.allCases) { brand in
                let state = model.status[brand] ?? .checking
                HStack(spacing: 10) {
                    BrandMark(brand: brand, size: 17, active: state.isConnected)
                    Text(brand.title)
                        .font(Theme.heading(13))
                        .frame(width: 62, alignment: .leading)
                    Text(detail(state))
                        .font(Theme.body(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)

                    if Integrations.enabled {
                        Button(state.isConnected ? "Disconnect" : "Connect") {
                            Task {
                                if state.isConnected {
                                    Connect.disconnect(brand)
                                } else {
                                    Connect.begin(brand)
                                }
                                await model.refresh()
                            }
                        }
                        .font(Theme.body(11))
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func detail(_ status: ConnectionsModel.Status) -> String {
        switch status {
        case .comingSoon:          return "Coming soon"
        case .checking:            return "Checking…"
        case .connected(let who):  return who
        case .disconnected:        return "Not connected"
        case .failed(let why):     return why
        }
    }

    // MARK: - Gesture

    private var gestureSection: some View {
        section("Gesture") {
            LabeledContent {
                Text("⌥Space").font(Theme.body(12)).foregroundStyle(.secondary)
            } label: {
                Text("Key").font(Theme.heading(13))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Hold to preview after \(Int(holdThreshold * 1000))ms")
                    .font(Theme.body(13))
                Slider(value: $holdThreshold, in: 0.1...0.6) { editing in
                    if !editing { Settings.holdThreshold = holdThreshold }
                }
                Text("Below this, a tap just runs. Anything destructive always waits "
                   + "for a hold.")
                    .font(Theme.body(11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
}

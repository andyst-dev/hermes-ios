import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var store: AppStore
    @State private var host = "http://macbook.local:8765"
    @State private var profile = "default"

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(HermesTheme.elevated)
                        .frame(width: 86, height: 86)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(HermesTheme.gold, HermesTheme.blue)
                }
                Text("Hermes Companion")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Your desktop agent, in your pocket.")
                    .font(.headline)
                    .foregroundStyle(HermesTheme.muted)
            }

            VStack(spacing: 14) {
                TextField("Hermes host", text: $host)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .padding(16)
                    .background(HermesTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                TextField("Profile", text: $profile)
                    .textInputAutocapitalization(.never)
                    .padding(16)
                    .background(HermesTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button(action: connect) {
                    HStack {
                        if case .connecting = store.connection { ProgressView().tint(.black) }
                        Text("Connect to Hermes")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(HermesTheme.gold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)
                }
                .disabled(isConnecting)
            }
            .padding(22)
            .glassPanel()
            .padding(.horizontal, 24)

            if case .failed(let message) = store.connection {
                Text(message)
                    .foregroundStyle(HermesTheme.red)
                    .font(.footnote)
                    .padding(.horizontal, 30)
            }
            Spacer()
        }
    }

    private var isConnecting: Bool {
        if case .connecting = store.connection { true } else { false }
    }

    private func connect() {
        guard let url = URL(string: host) else { return }
        Task {
            await store.connect(host: HermesHost(name: "Desktop Hermes", baseURL: url, profile: profile))
        }
    }
}

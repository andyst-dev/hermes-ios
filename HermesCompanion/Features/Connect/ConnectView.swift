import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var store: AppStore
    @State private var host = "http://macbook.local:8765"
    @State private var profile = "default"

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 24)

            VStack(spacing: 16) {
                HermesMark(size: 92)
                HermesWordmark()
                Text("Remote control for the agent that grows with you.")
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(HermesTheme.primary)
                    TextField("Hermes host", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(15)
                .background(HermesTheme.sidebar, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))

                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(HermesTheme.primary)
                    TextField("Profile", text: $profile)
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(15)
                .background(HermesTheme.sidebar, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))

                Button(action: connect) {
                    HStack(spacing: 10) {
                        if case .connecting = store.connection { ProgressView().tint(.white) }
                        Text("Connect to Hermes")
                            .font(.system(.callout, design: .monospaced).weight(.bold))
                            .tracking(0.4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(HermesTheme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(HermesTheme.primaryForeground)
                }
                .disabled(isConnecting)

                Button {} label: {
                    Label("Scan pairing QR", systemImage: "qrcode.viewfinder")
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                        .foregroundStyle(HermesTheme.foreground.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(18)
            .desktopPanel(cornerRadius: 24)
            .padding(.horizontal, 22)

            if case .failed(let message) = store.connection {
                Text(message)
                    .foregroundStyle(HermesTheme.red)
                    .font(.footnote)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 28)
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

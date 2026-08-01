import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var store: AppStore
    @State private var host = UserDefaults.standard.string(forKey: "hermes.host") ?? "http://127.0.0.1:8765"
    @State private var profile = UserDefaults.standard.string(forKey: "hermes.profile") ?? "default"
    @State private var token = ProcessInfo.processInfo.environment["HERMES_DASHBOARD_SESSION_TOKEN"] ?? KeychainStore.loadToken() ?? ""
    @State private var tokenSaveError: String?

    var body: some View {
        HermesMobileScreen(title: "Connect", subtitle: "Hermes Desktop bridge", icon: "desktopcomputer") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HermesMark(size: 82)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Thin iOS client. Tools, files, models and execution stay on Desktop.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HermesTheme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HermesMobileSection(title: "Desktop") {
                    connectionField(icon: "network", placeholder: "http://127.0.0.1:8765", text: $host, keyboard: .URL)
                    connectionField(icon: "person.crop.circle", placeholder: "default", text: $profile)
                    secureTokenField
                }

                Button(action: connect) {
                    HStack(spacing: 10) {
                        if case .connecting = store.connection { ProgressView().tint(HermesTheme.primaryForeground) }
                        Text("Connect to Hermes Desktop")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(HermesTheme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(HermesTheme.primaryForeground)
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)

                Button {} label: {
                    Label("Pairing QR coming next", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HermesTheme.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if let tokenSaveError {
                    Text(tokenSaveError)
                        .font(.system(size: 11))
                        .foregroundStyle(HermesTheme.red)
                }
                if case .failed(let message) = store.connection {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(HermesTheme.red)
                }
            }
        }
    }

    private var secureTokenField: some View {
        HStack(spacing: 9) {
            Image(systemName: "key")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HermesTheme.primary)
                .frame(width: 18)
            SecureField("Dashboard token optional", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(HermesTheme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(HermesTheme.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    private func connectionField(icon: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HermesTheme.primary)
                .frame(width: 18)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(HermesTheme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(HermesTheme.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    private var isConnecting: Bool {
        if case .connecting = store.connection { true } else { false }
    }

    private func connect() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProfile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedHost) else { return }
        do {
            try KeychainStore.saveToken(token)
            UserDefaults.standard.set(trimmedHost, forKey: "hermes.host")
            UserDefaults.standard.set(trimmedProfile.isEmpty ? "default" : trimmedProfile, forKey: "hermes.profile")
            tokenSaveError = nil
        } catch {
            tokenSaveError = error.localizedDescription
            return
        }
        Task {
            await store.connect(host: HermesHost(name: "Desktop Hermes", baseURL: url, profile: trimmedProfile.isEmpty ? "default" : trimmedProfile))
        }
    }
}

import SwiftUI

struct ConnectView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @State private var host = UserDefaults.standard.string(forKey: "hermes.host") ?? ProcessInfo.processInfo.environment["HERMES_MOBILE_BASE_URL"] ?? "http://127.0.0.1:8765"
    @State private var profile = UserDefaults.standard.string(forKey: "hermes.profile") ?? ProcessInfo.processInfo.environment["HERMES_PROFILE"] ?? "default"
    @State private var token = ProcessInfo.processInfo.environment["HERMES_DASHBOARD_SESSION_TOKEN"] ?? KeychainStore.loadToken() ?? ""
    @State private var showingAdvanced = false
    @State private var showingScanner = false
    @State private var tokenSaveError: String?
    @State private var copiedPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectOnboardingHeader()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    onboardingHero

                    HermesMobileSection(title: "First, install the plugin", icon: "puzzlepiece.extension.fill", accent: HermesTheme.primary) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("The Mac needs the Hermes Mobile plugin before pairing. Run this once in a terminal on the Mac:")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(HermesTheme.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                            pluginInstallCard
                            Text("Then start the Hermes dashboard — the pairing QR lives there. Stock Hermes, no patches, no VPN.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(HermesTheme.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HermesMobileSection(title: "Ask Hermes", icon: "quote.bubble.fill", accent: HermesTheme.primary) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("On your Mac, open Hermes Desktop and say:")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(HermesTheme.mutedForeground)
                            promptCard
                            Button(action: copyPrompt) {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedPrompt ? "check" : "doc.on.doc")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(copiedPrompt ? "Copied" : "Copy prompt")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(copiedPrompt ? HermesTheme.green : HermesTheme.primary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(HermesTheme.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 24)

                    HermesMobileSection(title: "Then scan", icon: "qrcode.viewfinder", accent: HermesTheme.primary) {
                        Text("Hermes will show a QR. Scan it here and this iPhone connects automatically.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button { showingScanner = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 15, weight: .bold))
                            Text("Scan QR")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(HermesTheme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(HermesTheme.primaryForeground)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) { showingAdvanced.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showingAdvanced ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("Advanced connection")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(HermesTheme.mutedForeground)
                    }
                    .buttonStyle(.plain)

                    if showingAdvanced {
                        HermesMobileSection(title: "Manual") {
                            HermesMobileRow(title: "Desktop bridge", subtitle: simplifiedHostLabel, icon: "network", accent: HermesTheme.primary)
                            HermesMobileRow(title: "Profile", subtitle: profile.isEmpty ? "default" : profile, icon: "folder", accent: HermesTheme.mutedForeground)
                            connectionField(icon: "network", placeholder: "http://127.0.0.1:8765", text: $host, keyboard: .URL)
                            connectionField(icon: "person.crop.circle", placeholder: "default", text: $profile)
                            secureTokenField
                            Button(action: connect) {
                                HStack(spacing: 10) {
                                    if case .connecting = store.connection { ProgressView().tint(HermesTheme.primaryForeground) }
                                    Text("Connect with these details")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(HermesTheme.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(HermesTheme.mutedForeground)
                            }
                            .buttonStyle(.plain)
                            .disabled(isConnecting)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let tokenSaveError {
                        Text(tokenSaveError)
                            .font(.system(size: 11))
                            .foregroundStyle(HermesTheme.red)
                    }
                    if case .failed(let message) = store.connection, shouldShowConnectionError(message) {
                        Text(cleanConnectionError(message))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .background(HermesTheme.sidebar.ignoresSafeArea())
        .sheet(isPresented: $showingScanner) {
            PairingQRCodeScanner { code in
                showingScanner = false
                Task { await pair(with: code) }
            } onError: { message in
                showingScanner = false
                tokenSaveError = message
            }
            .ignoresSafeArea()
        }
    }

    private var onboardingHero: some View {
        HStack(alignment: .center, spacing: 18) {
            HermesMark(size: 70)
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your iPhone")
                    .font(HermesTheme.brandTitle(size: 27))
                    .foregroundStyle(HermesTheme.ink)
                Text("No host. No token. Ask Hermes for a QR, then scan.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var promptCard: some View {
        Text(pairingPrompt)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(HermesTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HermesTheme.userBubbleBorder, lineWidth: 1))
    }

    private var pluginInstallCard: some View {
        Text("hermes plugins install andyst-dev/hermes-ios/plugin --enable")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(HermesTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesTheme.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    private var pairingPrompt: String {
        "Connecte mon iPhone à Hermes Companion"
    }

    private var secureTokenField: some View {
        HStack(spacing: 9) {
            Image(systemName: "key")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HermesTheme.primary)
                .frame(width: 18)
            SecureField("Dashboard token", text: $token)
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

    private var simplifiedHostLabel: String {
        guard let url = URL(string: host), let hostName = url.host else { return host }
        if hostName == "127.0.0.1" || hostName == "localhost" { return "Local simulator" }
        return hostName
    }

    private var isConnecting: Bool {
        if case .connecting = store.connection { true } else { false }
    }

    private func copyPrompt() {
        UIPasteboard.general.string = pairingPrompt
        withAnimation(.snappy) { copiedPrompt = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.snappy) { copiedPrompt = false }
            }
        }
    }

    private func shouldShowConnectionError(_ message: String) -> Bool {
        !message.localizedCaseInsensitiveContains("unauthorized")
    }

    private func cleanConnectionError(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("unauthorized") {
            return "Not paired yet. Ask Hermes for a QR, then scan."
        }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return "Connection failed. Check Advanced connection or scan a fresh QR."
        }
        return message
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

    @MainActor
    private func pair(with qrText: String) async {
        do {
            let payload = try DesktopPairingPayload.parse(qrText)
            // Plugin QRs embed the dashboard session token directly — no
            // round-trip needed. Standalone-bridge QRs fall back to the
            // code exchange below.
            if let embeddedToken = payload.token, !embeddedToken.isEmpty {
                host = payload.url.absoluteString
                profile = payload.profile
                token = embeddedToken
                try KeychainStore.saveToken(embeddedToken)
                UserDefaults.standard.set(host, forKey: "hermes.host")
                UserDefaults.standard.set(profile, forKey: "hermes.profile")
                tokenSaveError = nil
                await store.connect(host: HermesHost(name: "Desktop Hermes", baseURL: payload.url, profile: payload.profile))
                return
            }
            let pairURL = payload.url.appending(path: "api").appending(path: "mobile").appending(path: "pair")
            var request = URLRequest(url: pairURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(MobilePairRequest(code: payload.code, deviceName: UIDevice.current.name))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw PairingError.failed(String(data: data, encoding: .utf8) ?? "Pairing failed")
            }
            let paired = try JSONDecoder().decode(MobilePairResponse.self, from: data)
            host = paired.url.absoluteString
            profile = paired.profile
            token = paired.token
            try KeychainStore.saveToken(paired.token)
            UserDefaults.standard.set(host, forKey: "hermes.host")
            UserDefaults.standard.set(profile, forKey: "hermes.profile")
            tokenSaveError = nil
            await store.connect(host: HermesHost(name: "Desktop Hermes", baseURL: paired.url, profile: paired.profile))
        } catch {
            tokenSaveError = error.localizedDescription
        }
    }
}

private struct ConnectOnboardingHeader: View {
    @ObservedObject private var theme = ThemeManager.shared
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: -2) {
                Text("HERMES")
                    .font(HermesTheme.brandSerif(size: 28))
                    .tracking(0.8)
                    .foregroundStyle(HermesTheme.ink)
                Text("AGENT")
                    .font(HermesTheme.brandSerif(size: 20))
                    .tracking(1.2)
                    .foregroundStyle(HermesTheme.ink.opacity(0.94))
            }
            .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }
}

private struct DesktopPairingPayload: Decodable {
    let type: String
    let url: URL
    let profile: String
    let code: String
    // Present on plugin QR payloads: the dashboard session token is embedded
    // so the app can connect without a public /pair endpoint. Optional so
    // standalone-bridge QRs (code-only) keep working.
    var token: String?

    static func parse(_ raw: String) throws -> DesktopPairingPayload {
        guard let data = raw.data(using: .utf8) else { throw PairingError.failed("Invalid QR") }
        let payload = try JSONDecoder().decode(DesktopPairingPayload.self, from: data)
        guard payload.type == "hermes-mobile-pairing" else { throw PairingError.failed("Not a Hermes Desktop QR") }
        return payload
    }
}

private struct MobilePairRequest: Encodable {
    let code: String
    let deviceName: String
}

private struct MobilePairResponse: Decodable {
    let ok: Bool
    let url: URL
    let profile: String
    let token: String
}

private enum PairingError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingModels = false
    @State private var showingForgetPairingAlert = false
    @State private var actionStatus: String?

    var body: some View {
        HermesMobileScreen(title: "Settings", subtitle: connectionLabel, icon: "gearshape", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HermesMobileSection(title: "Connection", icon: "antenna.radiowaves.left.and.right", accent: connectionAccent) {
                        if case .connected(let host) = store.connection {
                            HermesMobileRow(title: "Host", subtitle: store.privacyMode ? "Connected desktop" : host.baseURL.absoluteString, icon: "desktopcomputer", accent: HermesTheme.green)
                            HermesMobileRow(title: "Profile", subtitle: host.profile, icon: "folder", accent: HermesTheme.primary)
                        } else {
                            HermesMobileRow(title: "Status", subtitle: connectionLabel, icon: "desktopcomputer", accent: connectionAccent)
                        }
                        HermesMobileRow(title: "Transport", subtitle: transportLabel, icon: "point.3.connected.trianglepath.dotted", accent: HermesTheme.mutedForeground)
                    }

                    HermesMobileSection(title: "Actions", icon: "bolt.fill", accent: HermesTheme.primary) {
                        SettingsActionRow(title: "Refresh desktop state", subtitle: "Reload sessions, models, tools", icon: "arrow.triangle.2.circlepath", accent: HermesTheme.primary) {
                            await run(.refresh, done: "Desktop state refreshed")
                        }
                        SettingsActionRow(title: "New chat", subtitle: "Start a clean mobile conversation", icon: "plus.message", accent: HermesTheme.primary) {
                            await run(.newChat, done: "New chat ready")
                        }
                        SettingsActionRow(title: "Continue last task", subtitle: "Send Continue in the selected chat", icon: "arrow.clockwise", accent: HermesTheme.warm) {
                            await run(.continueLast, done: "Continue sent")
                        }
                        SettingsActionRow(title: "Stop running turn", subtitle: store.isStreaming ? "Request stop on Desktop" : "No running turn", icon: "stop.fill", accent: HermesTheme.destructive) {
                            await run(.stop, done: "Stop requested")
                        }
                        .opacity(store.isStreaming ? 1 : 0.55)
                    }

                    HermesMobileSection(title: "Desktop controls", icon: "slider.horizontal.3", accent: HermesTheme.primary) {
                        SettingsButtonRow(title: "Model", subtitle: modelSubtitle, icon: "cpu", accent: HermesTheme.primary) {
                            showingModels = true
                        }
                        SettingsButtonRow(title: "Copy desktop URL", subtitle: copyURLSubtitle, icon: "doc.on.doc", accent: HermesTheme.mutedForeground) {
                            copyDesktopURL()
                        }
                        SettingsButtonRow(title: "Disconnect", subtitle: "Leave pairing saved for next launch", icon: "wifi.slash", accent: HermesTheme.warm) {
                            store.disconnect(clearPairing: false)
                            actionStatus = "Disconnected. Pairing is still saved."
                        }
                    }

                    HermesMobileSection(title: "Privacy", icon: "eye.slash", accent: HermesTheme.warm) {
                        HStack(spacing: 10) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HermesTheme.warm)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Privacy mode")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(HermesTheme.ink)
                                Text("Hide local paths and raw endpoints")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                            }
                            Spacer()
                            Toggle("", isOn: $store.privacyMode)
                                .labelsHidden()
                                .tint(HermesTheme.ring)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        SettingsButtonRow(title: "Forget pairing", subtitle: "Clear Keychain token and saved desktop", icon: "key.slash", accent: HermesTheme.destructive) {
                            showingForgetPairingAlert = true
                        }
                    }

                    HermesMobileSection(title: "What works", icon: "checkmark.seal", accent: HermesTheme.green) {
                        HermesMobileRow(title: "Real sessions", subtitle: "Desktop/CLI/gateway conversations", icon: "message", accent: HermesTheme.green)
                        HermesMobileRow(title: "Models", subtitle: "Read and switch Desktop model", icon: "cpu", accent: HermesTheme.green)
                        HermesMobileRow(title: "Remote chat", subtitle: "Send prompts through Desktop bridge", icon: "paperplane", accent: HermesTheme.green)
                        HermesMobileRow(title: "Next", subtitle: "Streaming, files, approvals", icon: "ellipsis", accent: HermesTheme.mutedForeground)
                    }

                    if let actionStatus {
                        Text(actionStatus)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .padding(.horizontal, 3)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $showingModels) {
            ModelPickerView()
                .environmentObject(store)
        }
        .alert("Forget pairing?", isPresented: $showingForgetPairingAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive) {
                store.disconnect(clearPairing: true)
                actionStatus = "Pairing cleared. Scan a QR to reconnect."
            }
        } message: {
            Text("This clears the saved mobile token and Desktop URL from this iPhone.")
        }
    }

    private var connectionLabel: String {
        switch store.connection {
        case .connected(let host): return "\(host.profile) · ready"
        case .connecting: return "connecting"
        case .failed: return "not paired"
        case .disconnected: return "not connected"
        }
    }

    private var connectionAccent: Color {
        if case .connected = store.connection { return HermesTheme.green }
        if case .connecting = store.connection { return HermesTheme.primary }
        return HermesTheme.mutedForeground
    }

    private var transportLabel: String {
        if ProcessInfo.processInfo.environment["HERMES_DEMO_CONNECTED"] == "1" {
            return "Demo mock"
        }
        if case .connected = store.connection {
            return "HTTP mobile bridge"
        }
        return "Not connected"
    }

    private var modelSubtitle: String {
        if let model = store.activeModel {
            return model.providerName.map { "\($0) · \(model.displayName)" } ?? model.displayName
        }
        return "Choose active Desktop model"
    }

    private var copyURLSubtitle: String {
        if case .connected(let host) = store.connection {
            return store.privacyMode ? "Copy connected desktop URL" : host.baseURL.absoluteString
        }
        return "No connected desktop"
    }

    private func run(_ command: MobileCommand, done: String) async {
        await store.runCommand(command)
        actionStatus = done
    }

    private func copyDesktopURL() {
        guard case .connected(let host) = store.connection else {
            actionStatus = "Connect to Desktop first."
            return
        }
        UIPasteboard.general.string = host.baseURL.absoluteString
        actionStatus = "Desktop URL copied."
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let action: () async -> Void
    @State private var running = false

    var body: some View {
        Button {
            guard !running else { return }
            running = true
            Task {
                await action()
                await MainActor.run { running = false }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(HermesTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                }
                Spacer(minLength: 0)
                if running {
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(HermesTheme.primary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(HermesTheme.card.opacity(0.26), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsButtonRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(HermesTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(HermesTheme.card.opacity(0.26), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @State private var showingModels = false
    @State private var showingFiles = false
    @State private var showingCron = false
    @State private var showingSkillsMemory = false
    @State private var showingForgetPairingAlert = false
    @State private var showingUpdateConfirmation = false
    @State private var showingToolOutput = false
    @State private var showingWhatsNew = false
    @State private var showingStats = false
    @State private var actionStatus: String?
    @AppStorage("hermes.debugAutoConnect") private var debugAutoConnect = false
    @AppStorage("hermes.faceidLock") private var faceIDLock = false

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

                    HermesMobileSection(title: "Desktop controls", icon: "slider.horizontal.3", accent: HermesTheme.primary) {
                        SettingsButtonRow(title: "Model", subtitle: modelSubtitle, icon: "cpu", accent: HermesTheme.primary) {
                            showingModels = true
                        }
                        SettingsButtonRow(title: "Files", subtitle: "Browse Desktop managed files", icon: "folder", accent: HermesTheme.primary) {
                            showingFiles = true
                        }
                        SettingsButtonRow(title: "Cron jobs", subtitle: "Scheduled gateway jobs", icon: "clock.badge.checkmark", accent: HermesTheme.primary) {
                            showingCron = true
                        }
                        SettingsButtonRow(title: "Skills & memory", subtitle: "Desktop agent skills and persistent memory", icon: "brain.head.profile", accent: HermesTheme.primary) {
                            showingSkillsMemory = true
                        }
                        SettingsButtonRow(title: "Copy desktop URL", subtitle: copyURLSubtitle, icon: "doc.on.doc", accent: HermesTheme.mutedForeground) {
                            copyDesktopURL()
                        }
                        SettingsButtonRow(title: "Disconnect", subtitle: "Leave pairing saved for next launch", icon: "wifi.slash", accent: HermesTheme.warm) {
                            store.disconnect(clearPairing: false)
                            actionStatus = "Disconnected. Pairing is still saved."
                        }
                    }

                    HermesMobileSection(title: "Remote access", icon: "network", accent: HermesTheme.primary) {
                        HermesMobileRow(
                            title: store.tunnelStatus.active ? "Tunnel active" : "Tunnel off",
                            subtitle: store.tunnelStatus.active
                                ? store.tunnelStatus.publicUrl
                                : "Pair from anywhere — no VPN",
                            icon: "globe",
                            accent: store.tunnelStatus.active ? HermesTheme.green : HermesTheme.mutedForeground
                        )
                        if !store.tunnelStatus.error.isEmpty {
                            Text(store.tunnelStatus.error)
                                .font(.system(size: 11))
                                .foregroundStyle(HermesTheme.red)
                                .padding(.horizontal, 10)
                        }
                        if store.tunnelStatus.active {
                            SettingsButtonRow(title: "Copy public URL", subtitle: "Pair from anywhere with this link", icon: "doc.on.doc", accent: HermesTheme.green) {
                                UIPasteboard.general.string = store.tunnelStatus.publicUrl
                                actionStatus = "Public URL copied."
                            }
                            SettingsButtonRow(title: "Stop remote access", subtitle: "Close the tunnel", icon: "xmark.circle", accent: HermesTheme.warm) {
                                Task { await store.stopTunnel() }
                            }
                        } else {
                            SettingsButtonRow(title: "Start remote access", subtitle: "Open a public HTTPS tunnel (cloudflared)", icon: "globe.europe.africa.fill", accent: HermesTheme.primary) {
                                Task { await store.startTunnel() }
                            }
                        }
                    }
                    .onAppear {
                        Task { await store.refreshTunnelStatus() }
                        Task { await store.refreshCron() }
                        Task { await store.refreshSkillsMemory() }
                        Task { await store.refreshUpdateStatus() }
                    }

                    HermesMobileSection(title: "Appearance", icon: "paintpalette", accent: HermesTheme.ring) {
                        HStack(spacing: 10) {
                            Image(systemName: "sun.max")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HermesTheme.ring)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cream theme")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(HermesTheme.ink)
                                Text("Hermès-style light: cream paper, chocolate ink, saddle-orange accents")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { theme.mode == .cream },
                                set: { theme.mode = $0 ? .cream : .ember }
                            ))
                            .labelsHidden()
                            .toggleStyle(PlutoToggleStyle())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }

                    HermesMobileSection(title: "Desktop maintenance", icon: "wrench.and.screwdriver", accent: HermesTheme.primary) {
                        SettingsButtonRow(title: "Hermes doctor", subtitle: "Check configuration and dependencies", icon: "stethoscope", accent: HermesTheme.green) {
                            Task { await store.runDesktopTool(.doctor) }
                            showingToolOutput = true
                        }
                        SettingsButtonRow(title: "Hermes update", subtitle: updateSubtitle, icon: "arrow.down.circle", accent: updateAccent) {
                            showingUpdateConfirmation = true
                        }
                        if store.updateStatus?.updateAvailable == true {
                            SettingsButtonRow(title: "What's new", subtitle: "\(store.updateStatus?.highlights.count ?? 0) incoming changes", icon: "sparkles", accent: HermesTheme.warm) {
                                showingWhatsNew = true
                            }
                        }
                    }
                    .alert("Update Hermes?", isPresented: $showingUpdateConfirmation) {
                        Button("Update") {
                            Task { await store.runDesktopTool(.update) }
                            showingToolOutput = true
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(updateConfirmationMessage)
                    }

                    HermesMobileSection(title: "Usage", icon: "chart.bar.xaxis", accent: HermesTheme.warm) {
                        SettingsButtonRow(title: "Usage stats", subtitle: "Tokens and cost per model", icon: "chart.bar.xaxis", accent: HermesTheme.warm) {
                            showingStats = true
                        }
                    }

                    HermesMobileSection(title: "Security", icon: "lock.shield", accent: HermesTheme.green) {
                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HermesTheme.green)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Face ID lock")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(HermesTheme.ink)
                                Text("Require Face ID (or the device passcode) when the app opens or returns to the foreground")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                            }
                            Spacer()
                            Toggle("", isOn: $faceIDLock)
                                .labelsHidden()
                                .toggleStyle(PlutoToggleStyle())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }

                    HermesMobileSection(title: "Debug", icon: "wrench.and.screwdriver", accent: HermesTheme.mutedForeground) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.horizontal.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HermesTheme.mutedForeground)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-connect local desktop")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(HermesTheme.ink)
                                Text("Skip the Connect screen: open 127.0.0.1:8765 directly (dev only)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                            }
                            Spacer()
                            Toggle("", isOn: $debugAutoConnect)
                                .labelsHidden()
                                .toggleStyle(PlutoToggleStyle())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        Text("The app still needs a saved pairing token — set it once via the QR screen and it will auto-connect on every launch.")
                            .font(.system(size: 10))
                            .foregroundStyle(HermesTheme.mutedForeground.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
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
                                .toggleStyle(PlutoToggleStyle())
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
                        HermesMobileRow(title: "Live streaming", subtitle: "Tokens arrive as the Desktop generates", icon: "bolt", accent: HermesTheme.green)
                        HermesMobileRow(title: "Command approvals", subtitle: "Approve or deny dangerous commands", icon: "exclamationmark.triangle", accent: HermesTheme.green)
                        HermesMobileRow(title: "Files", subtitle: "Browse and preview Desktop files", icon: "folder", accent: HermesTheme.green)
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
        .sheet(isPresented: $showingFiles) {
            FilesView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingCron) {
            CronJobsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingSkillsMemory) {
            SkillsMemoryView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingToolOutput) {
            DesktopToolOutputView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingStats) {
            StatsView()
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

    private var updateSubtitle: String {
        guard let status = store.updateStatus else { return "Checking for updates…" }
        if status.updateAvailable {
            return "Update available — \(status.highlights.count) incoming changes"
        }
        return "You're up to date"
    }

    /// Shown in the "Update Hermes?" confirmation so tapping the update row
    /// reveals the human-readable release notes before anything runs.
    private var updateConfirmationMessage: String {
        var lines: [String] = []
        if let status = store.updateStatus, status.updateAvailable, !status.notes.isEmpty {
            lines.append("What's new:")
            for noteSection in status.notes {
                lines.append(noteSection.section + ":")
                for item in noteSection.items {
                    lines.append("  • " + item)
                }
            }
            lines.append("")
        }
        lines.append("Pulls the latest hermes from git and reinstalls dependencies. Restart the dashboard after it finishes.")
        return lines.joined(separator: "\n")
    }

    private var updateAccent: Color {
        if store.updateStatus?.updateAvailable == true { return HermesTheme.warm }
        if store.updateStatus != nil { return HermesTheme.green }
        return HermesTheme.mutedForeground
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

    private func copyDesktopURL() {
        guard case .connected(let host) = store.connection else {
            actionStatus = "Connect to Desktop first."
            return
        }
        UIPasteboard.general.string = host.baseURL.absoluteString
        actionStatus = "Desktop URL copied."
    }
}

struct SettingsButtonRow: View {
    @ObservedObject private var theme = ThemeManager.shared
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


private struct DesktopToolOutputView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HermesMobileScreen(title: store.toolTitle, subtitle: "Desktop CLI output", icon: "terminal", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if store.toolRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(HermesTheme.mutedForeground)
                        }
                        .padding(.vertical, 6)
                    }
                    if !store.toolIssues.isEmpty {
                        HermesMobileSection(title: "Issues found (\(store.toolIssues.count))", icon: "exclamationmark.triangle", accent: HermesTheme.warm) {
                            ForEach(Array(store.toolIssues.enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.problem)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(HermesTheme.warm)
                                    Text("→ \(issue.solution)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(HermesTheme.mutedForeground)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    Text(store.toolOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HermesTheme.ink.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct WhatsNewView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @State private var showFullChangelog = false

    var body: some View {
        HermesMobileScreen(title: "What's new", subtitle: "Incoming changes", icon: "sparkles", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let status = store.updateStatus {
                        if status.updateAvailable {
                            if !status.notes.isEmpty {
                                ForEach(status.notes, id: \.section) { noteSection in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(noteSection.section.uppercased())
                                            .font(.system(size: 11, weight: .bold))
                                            .tracking(0.9)
                                            .foregroundStyle(HermesTheme.warm)
                                        ForEach(noteSection.items, id: \.self) { item in
                                            HStack(alignment: .top, spacing: 7) {
                                                Circle()
                                                    .fill(HermesTheme.primary)
                                                    .frame(width: 5, height: 5)
                                                    .padding(.top, 5)
                                                Text(item)
                                                    .font(.system(size: 12.5))
                                                    .foregroundStyle(HermesTheme.ink.opacity(0.9))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            } else {
                                ForEach(Array(status.highlights.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(HermesTheme.ink.opacity(0.85))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            Button {
                                showFullChangelog.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showFullChangelog ? "chevron.up" : "chevron.down")
                                    Text(showFullChangelog ? "Hide full changelog" : "See all changes in detail")
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(HermesTheme.primary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                            if showFullChangelog {
                                Text(status.fullChangelog.isEmpty ? "No detailed changelog available." : status.fullChangelog)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(HermesTheme.ink.opacity(0.7))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Text("You're up to date.")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(HermesTheme.green)
                            Text(status.output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(HermesTheme.mutedForeground)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("Checking for updates…")
                            .font(.system(size: 13))
                            .foregroundStyle(HermesTheme.mutedForeground)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .task {
            await store.refreshUpdateStatus()
        }
    }
}

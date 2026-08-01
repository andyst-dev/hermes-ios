import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HermesMobileScreen(title: "Settings", subtitle: connectionLabel, icon: "gearshape", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HermesMobileSection(title: "Connection", icon: "antenna.radiowaves.left.and.right", accent: HermesTheme.green) {
                        if case .connected(let host) = store.connection {
                            HermesMobileRow(title: "Host", subtitle: store.privacyMode ? "Connected desktop" : host.baseURL.absoluteString, icon: "desktopcomputer", accent: HermesTheme.green)
                            HermesMobileRow(title: "Profile", subtitle: host.profile, icon: "folder", accent: HermesTheme.primary)
                        }
                        HermesMobileRow(title: "Transport", subtitle: transportLabel, icon: "point.3.connected.trianglepath.dotted", accent: HermesTheme.mutedForeground)
                    }

                    HermesMobileSection(title: "Desktop parity", icon: "rectangle.split.3x1", accent: HermesTheme.primary) {
                        HermesMobileRow(title: "Conversations", subtitle: "Sessions, sticky prompts, streaming shell", icon: "message", accent: HermesTheme.primary)
                        HermesMobileRow(title: "Desktop state", subtitle: "Models, profiles, tools, files, jobs", icon: "sidebar.right", accent: HermesTheme.primary)
                        HermesMobileRow(title: "Approvals", subtitle: "Mobile notifications and actions next", icon: "hand.raised", accent: HermesTheme.warm)
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
                        HermesMobileRow(title: "Keychain pairing", subtitle: "Revocable mobile token later", icon: "key", accent: HermesTheme.primary)
                    }

                    HermesMobileSection(title: "Roadmap", icon: "map", accent: HermesTheme.mutedForeground) {
                        HermesMobileRow(title: "QR pairing", subtitle: "Pair this iPhone with desktop Hermes", icon: "qrcode", accent: HermesTheme.primary)
                        HermesMobileRow(title: "Files and voice", subtitle: "Uploads, previews, audio prompts", icon: "paperclip", accent: HermesTheme.mutedForeground)
                        HermesMobileRow(title: "Push approvals", subtitle: "Approve long-running agent work", icon: "bell.badge", accent: HermesTheme.warm)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .presentationDetents([.large])
    }

    private var connectionLabel: String {
        if case .connected(let host) = store.connection { return "\(host.profile) · gateway ready" }
        return "not connected"
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
}

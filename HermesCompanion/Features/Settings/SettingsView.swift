import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    if case .connected(let host) = store.connection {
                        LabeledContent("Host", value: store.privacyMode ? "Connected desktop" : host.baseURL.absoluteString)
                        LabeledContent("Profile", value: host.profile)
                    }
                    LabeledContent("Transport", value: "Mock / API-ready")
                }

                Section("Desktop parity") {
                    Label("Sessions, chat streaming, stop, command palette", systemImage: "message")
                    Label("Models, profiles, tools, files, jobs, approvals", systemImage: "sidebar.right")
                    Label("iPad three-column shell, iPhone sheets", systemImage: "rectangle.split.3x1")
                }

                Section("Privacy") {
                    Toggle("Privacy mode", isOn: $store.privacyMode)
                    Label("Public surfaces hide local paths by default", systemImage: "eye.slash")
                    Label("Tokens belong in Keychain when pairing is wired", systemImage: "key")
                }

                Section("Roadmap") {
                    Label("QR pairing", systemImage: "qrcode")
                    Label("Photos, files, and voice prompts", systemImage: "paperclip")
                    Label("Push notifications for approvals", systemImage: "bell.badge")
                    Label("Live Activities for long agent runs", systemImage: "waveform.path.ecg")
                }
            }
            .scrollContentBackground(.hidden)
            .background(HermesTheme.background)
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

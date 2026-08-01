import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    if case .connected(let host) = store.connection {
                        LabeledContent("Host", value: host.baseURL.absoluteString)
                        LabeledContent("Profile", value: host.profile)
                    }
                    LabeledContent("Transport", value: "Mock / API-ready")
                }
                Section("Privacy") {
                    Label("Public surfaces hide local paths by default", systemImage: "eye.slash")
                    Label("Tokens belong in Keychain when pairing is wired", systemImage: "key")
                }
                Section("Roadmap") {
                    Label("QR pairing", systemImage: "qrcode")
                    Label("Photos, files, and voice prompts", systemImage: "paperclip")
                    Label("Push notifications for approvals", systemImage: "bell.badge")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

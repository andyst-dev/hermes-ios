import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            BackgroundView()
            Group {
                switch store.connection {
                case .connected:
                    MainShellView(showingSettings: $showingSettings)
                default:
                    ConnectView()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
        }
    }
}

private struct MainShellView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool

    var body: some View {
        NavigationSplitView {
            SessionListView(showingSettings: $showingSettings)
                .navigationTitle("Hermes")
        } detail: {
            ChatView()
                .navigationTitle(store.selectedSession?.title ?? "New Session")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BackgroundView: View {
    var body: some View {
        LinearGradient(colors: [HermesTheme.background, Color(red: 0.055, green: 0.067, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(HermesTheme.blue.opacity(0.25))
                    .frame(width: 280, height: 280)
                    .blur(radius: 80)
                    .offset(x: 120, y: -120)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(HermesTheme.gold.opacity(0.16))
                    .frame(width: 320, height: 320)
                    .blur(radius: 95)
                    .offset(x: -160, y: 140)
            }
            .ignoresSafeArea()
    }
}

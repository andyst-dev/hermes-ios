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
        .tint(HermesTheme.primary)
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
        LinearGradient(colors: [HermesTheme.chrome, HermesTheme.sidebar], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(HermesTheme.primary.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: 130, y: -140)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(HermesTheme.warm.opacity(0.14))
                    .frame(width: 320, height: 320)
                    .blur(radius: 85)
                    .offset(x: -160, y: 140)
            }
            .ignoresSafeArea()
    }
}

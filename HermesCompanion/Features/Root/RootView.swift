import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var theme = ThemeManager.shared
    @State private var showingSettings = false
    @State private var showingCommands = false
    @State private var showingInspector = false
    @State private var showingModels = false

    var body: some View {
        ZStack {
            BackgroundView()
            Group {
                switch store.connection {
                case .connected:
                    MainShellView(
                        showingSettings: $showingSettings,
                        showingCommands: $showingCommands,
                        showingInspector: $showingInspector,
                        showingModels: $showingModels
                    )
                default:
                    ConnectView()
                }
            }
            // App lock removed (Coming soon in Settings) — no LockView overlay.
        }
        .tint(HermesTheme.ring)
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $showingCommands) {
            CommandPaletteView().environmentObject(store)
        }

    }
}

private struct MainShellView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var showingSettings: Bool
    @Binding var showingCommands: Bool
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingChat = false

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactShell
            } else {
                splitShell
            }
        }
        .onChange(of: store.deepLinkSessionID) { _, _ in
            // Widget deep link (hermes://session/… or hermes://new-chat):
            // bring up the chat pane, then clear the flag.
            guard store.deepLinkSessionID != nil else { return }
            withAnimation(.snappy) { showingChat = true }
            store.deepLinkSessionID = nil
        }
    }

    private var compactShell: some View {
        SessionListView(showingSettings: $showingSettings, onSessionSelected: {
            withAnimation(.snappy) { showingChat = true }
        }, onOpenCommands: { showingCommands = true })
        .fullScreenCover(isPresented: $showingChat) {
            ChatView(
                showingInspector: $showingInspector,
                showingModels: $showingModels,
                onBack: { showingChat = false }
            )
            .environmentObject(store)
        }
    }

    private var splitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SessionListView(showingSettings: $showingSettings, onSessionSelected: {
                withAnimation(.snappy) { columnVisibility = .detailOnly }
            }, onOpenCommands: { showingCommands = true })
                .navigationTitle("Hermes")
        } content: {
            ChatView(showingInspector: $showingInspector, showingModels: $showingModels)
                .navigationTitle(store.selectedSession?.title ?? "New Session")
                .navigationBarTitleDisplayMode(.inline)
        } detail: {
            InspectorView()
                .navigationTitle("Conversation")
        }
    }
}

private struct BackgroundView: View {
    var body: some View {
        LinearGradient(colors: [HermesTheme.background, HermesTheme.sidebar], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(HermesTheme.ring.opacity(0.20))
                    .frame(width: 280, height: 280)
                    .blur(radius: 78)
                    .offset(x: 130, y: -140)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(HermesTheme.userBubbleBorder.opacity(0.34))
                    .frame(width: 320, height: 320)
                    .blur(radius: 95)
                    .offset(x: -160, y: 140)
            }
            .ignoresSafeArea()
    }
}

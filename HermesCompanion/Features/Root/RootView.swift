import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSettings = false
    @State private var showingCommands = false
    @State private var showingInspector = false
    @State private var showingModels = false
    @State private var showingTerminal = false

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
                        showingModels: $showingModels,
                        showingTerminal: $showingTerminal
                    )
                default:
                    ConnectView()
                }
            }
        }
        .tint(HermesTheme.ring)
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $showingCommands) {
            CommandPaletteView().environmentObject(store)
        }
        .sheet(isPresented: $showingInspector) {
            NavigationStack { InspectorView().navigationTitle("Desktop State") }
                .environmentObject(store)
        }
        .sheet(isPresented: $showingModels) {
            ModelPickerView().environmentObject(store)
        }
        .sheet(isPresented: $showingTerminal) {
            TerminalView().environmentObject(store)
        }
    }
}

private struct MainShellView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool
    @Binding var showingCommands: Bool
    @Binding var showingInspector: Bool
    @Binding var showingModels: Bool
    @Binding var showingTerminal: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SessionListView(showingSettings: $showingSettings)
                .navigationTitle("Hermes")
        } content: {
            ChatView(showingCommands: $showingCommands, showingInspector: $showingInspector, showingModels: $showingModels, showingTerminal: $showingTerminal)
                .navigationTitle(store.selectedSession?.title ?? "New Session")
                .navigationBarTitleDisplayMode(.inline)
        } detail: {
            InspectorView()
                .navigationTitle("Desktop State")
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

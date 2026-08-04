import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var commands: [MobileCommand] {
        // New chat lives in the sessions list "+" button; the palette is for
        // conversation actions only (no duplicate entry points).
        let all = MobileCommand.allCases.filter { $0 != .newChat }
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HermesMobileScreen(title: "Commands", subtitle: "mobile actions · desktop controlled", icon: "command", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HermesMobileSearchField(placeholder: "Search commands…", text: $query)

                    HermesMobileSection(title: "Actions", icon: "bolt", accent: HermesTheme.primary) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(commands) { command in
                                Button {
                                    Task {
                                        await store.runCommand(command)
                                        dismiss()
                                    }
                                } label: {
                                    HermesMobileRow(
                                        title: command.title,
                                        subtitle: commandSubtitle(command),
                                        icon: command.icon,
                                        accent: commandAccent(command),
                                        selected: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func commandSubtitle(_ command: MobileCommand) -> String {
        switch command {
        case .newChat: "Start a fresh desktop session"
        case .stop: "Stop the running turn"
        case .continueLast: "Send Continue into the selected chat"
        case .togglePrivacy: store.privacyMode ? "Currently hiding private details" : "Raw local details visible"
        case .refresh: "Reload sessions, models, and desktop state"
        }
    }

    private func commandAccent(_ command: MobileCommand) -> Color {
        switch command {
        case .stop: HermesTheme.destructive
        case .continueLast, .refresh: HermesTheme.primary
        case .togglePrivacy: HermesTheme.warm
        case .newChat: HermesTheme.green
        }
    }
}

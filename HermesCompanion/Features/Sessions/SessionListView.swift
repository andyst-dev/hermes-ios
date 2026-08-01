import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool
    var onSessionSelected: () -> Void = {}
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            MobileSessionsHeader(showingSettings: $showingSettings, onNewSession: openNewSession)
            ScrollView(showsIndicators: false) {
                let regularSessions = visibleSessions(excluding: "telegram")
                let telegramSessions = visibleSessions(only: "telegram")
                let hasResults = !regularSessions.isEmpty || !telegramSessions.isEmpty

                VStack(alignment: .leading, spacing: 18) {
                    MobileQuickFilters()
                    SidebarSearchField(text: $searchText)
                    if store.selectedSourceFilter == "all" {
                        PinnedSection()
                    }
                    if shouldShowRegularSection(sessions: regularSessions) {
                        SessionSourceSection(
                            title: regularSectionTitle,
                            icon: regularSectionIcon,
                            sessions: regularSessions,
                            searchText: searchText,
                            onSessionSelected: onSessionSelected
                        )
                    }
                    if shouldShowTelegramSection(sessions: telegramSessions) {
                        SessionSourceSection(
                            title: "Telegram",
                            icon: "paperplane.circle.fill",
                            accent: Color(red: 0.180, green: 0.620, blue: 0.920),
                            sessions: telegramSessions,
                            searchText: searchText,
                            onSessionSelected: onSessionSelected
                        )
                    }
                    if !hasResults {
                        EmptySessionsState(filter: store.selectedSourceFilter, searchText: searchText)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 96)
            }
            SidebarFooter(showingSettings: $showingSettings)
        }
        .background(HermesTheme.sidebar)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var selectedFilter: String { store.selectedSourceFilter.lowercased() }

    private var regularSectionTitle: String {
        switch selectedFilter {
        case "desktop": "Desktop"
        case "cli": "CLI"
        default: "Sessions"
        }
    }

    private var regularSectionIcon: String {
        switch selectedFilter {
        case "desktop": "macwindow"
        case "cli": "terminal"
        default: "checkerboard.rectangle"
        }
    }

    private func shouldShowRegularSection(sessions: [HermesSession]) -> Bool {
        selectedFilter != "telegram" && !sessions.isEmpty
    }

    private func shouldShowTelegramSection(sessions: [HermesSession]) -> Bool {
        (selectedFilter == "all" || selectedFilter == "telegram") && !sessions.isEmpty
    }

    private func visibleSessions(only source: String? = nil, excluding excludedSource: String? = nil) -> [HermesSession] {
        store.sessions.filter { session in
            let sessionSource = (session.source ?? "desktop").lowercased()
            let selectedSource = store.selectedSourceFilter.lowercased()
            if selectedSource != "all", sessionSource != selectedSource { return false }
            if let source, sessionSource != source { return false }
            if let excludedSource, sessionSource == excludedSource { return false }
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            let needle = searchText.lowercased()
            return session.title.lowercased().contains(needle) || session.subtitle.lowercased().contains(needle)
        }
    }

    private func openNewSession() {
        Task {
            await store.runCommand(.newChat)
            onSessionSelected()
        }
    }
}

private struct MobileSessionsHeader: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool
    let onNewSession: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Chats")
                    .font(HermesTheme.brandTitle(size: 25))
                    .foregroundStyle(HermesTheme.ink)
                HStack(spacing: 6) {
                    StatusDot(color: HermesTheme.green)
                    Text(connectionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HermesTheme.mutedForeground)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onNewSession) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HermesTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var connectionLabel: String {
        if case .connected(let host) = store.connection { return "\(host.profile) · gateway ready" }
        return "offline"
    }
}

private struct MobileQuickFilters: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.availableSources, id: \.self) { source in
                    Button {
                        store.selectedSourceFilter = source
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: source))
                                .font(.system(size: 11, weight: .semibold))
                            Text(label(for: source))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(source == store.selectedSourceFilter ? HermesTheme.primary : HermesTheme.mutedForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(source == store.selectedSourceFilter ? HermesTheme.userBubble : HermesTheme.card.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func label(for source: String) -> String {
        switch source {
        case "all": "All"
        case "telegram": "Telegram"
        case "desktop": "Desktop"
        case "cli": "CLI"
        default: source.capitalized
        }
    }

    private func icon(for source: String) -> String {
        switch source {
        case "telegram": "paperplane.circle.fill"
        case "desktop": "macwindow"
        case "cli": "terminal"
        default: "bubble.left.and.bubble.right"
        }
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.55))
            TextField("Search sessions…", text: $text)
                .font(.system(size: 13))
                .foregroundStyle(HermesTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(HermesTheme.background.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PinnedSection: View {
    var body: some View {
        SidebarSection(title: "Pinned", icon: "checkerboard.rectangle") {
            HStack(spacing: 9) {
                Image(systemName: "pin.slash")
                    .font(.system(size: 11, weight: .medium))
                Text("Long-press a chat to pin")
                    .font(.system(size: 12))
            }
            .foregroundStyle(HermesTheme.mutedForeground.opacity(0.72))
            .padding(.horizontal, 5)
            .padding(.top, 1)
        }
    }
}

private struct EmptySessionsState: View {
    let filter: String
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HermesTheme.ink.opacity(0.8))
            Text("Only relevant sections are shown for the active source.")
                .font(.system(size: 11))
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(HermesTheme.card.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(HermesTheme.stroke.opacity(0.8), lineWidth: 1))
    }

    private var title: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matching sessions" }
        return "No \(filter == "all" ? "" : filter + " ")sessions"
    }
}

private struct SessionSourceSection: View {
    @EnvironmentObject private var store: AppStore
    let title: String
    let icon: String
    var accent: Color = HermesTheme.mutedForeground
    let sessions: [HermesSession]
    let searchText: String
    let onSessionSelected: () -> Void

    var body: some View {
        SidebarSection(title: title, icon: icon, accent: accent) {
            if sessions.isEmpty {
                Text(searchText.isEmpty ? "No sessions yet" : "No matching sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
                    .padding(.horizontal, 6)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sessionGroups, id: \.title) { group in
                        if group.title != "Today" || title.lowercased() == "telegram" {
                            SidebarGroupLabel(title: group.title)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(group.sessions) { session in
                                Button {
                                    Task {
                                        await store.select(session: session)
                                        onSessionSelected()
                                    }
                                } label: {
                                    SidebarSessionRow(session: session, selected: session.id == store.selectedSessionID)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sessionGroups: [(title: String, sessions: [HermesSession])] {
        if title.lowercased() == "telegram" { return [("Telegram", sessions)] }
        let ordered = sessions
        let chunks: [(String, [HermesSession])] = [
            ("Today", Array(ordered.prefix(3))),
            ("Yesterday", Array(ordered.dropFirst(3).prefix(3))),
            ("Earlier this week", Array(ordered.dropFirst(6).prefix(4))),
            ("Last week", Array(ordered.dropFirst(10)))
        ]
        return chunks.filter { !$0.1.isEmpty }
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let icon: String
    var accent: Color = HermesTheme.mutedForeground
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(HermesTheme.ink.opacity(0.88))
                Spacer()
                if title.lowercased() == "sessions" {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.62))
                }
            }
            .padding(.horizontal, 4)
            content
        }
    }
}

private struct SidebarGroupLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.75))
            Rectangle()
                .fill(HermesTheme.border.opacity(0.68))
                .frame(height: 1)
        }
        .padding(.top, 2)
        .padding(.horizontal, 4)
    }
}

private struct SidebarSessionRow: View {
    let session: HermesSession
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusColor.opacity(selected ? 1.0 : 0.55))
                .frame(width: 4.5, height: 4.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? HermesTheme.ink : HermesTheme.ink.opacity(0.75))
                    .lineLimit(1)
                if selected || (session.source ?? "").lowercased() == "telegram" {
                    Text(session.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, selected ? 7 : 5)
        .background(selected ? HermesTheme.userBubble : Color.clear, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch session.status {
        case .idle: HermesTheme.mutedForeground
        case .running: HermesTheme.primary
        case .waitingApproval: HermesTheme.warm
        case .failed: HermesTheme.red
        case .completed: HermesTheme.mutedForeground
        }
    }
}

private struct SidebarFooter: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: HermesTheme.green)
            Text("Gateway ready")
            Text("·")
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.48))
            Image(systemName: "folder")
            Text(profileLabel)
                Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.82))
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(HermesTheme.sidebar.opacity(0.98))
    }

    private var profileLabel: String {
        if case .connected(let host) = store.connection { return host.profile }
        return "default"
    }
}

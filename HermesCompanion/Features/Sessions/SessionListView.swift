import SwiftUI

struct SessionListView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool
    var onSessionSelected: () -> Void = {}
    var onOpenCommands: () -> Void = {}
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            MobileSessionsHeader(showingSettings: $showingSettings, onNewSession: openNewSession, onOpenCommands: onOpenCommands, onOpenArchived: { showingArchived = true })
            ScrollView(showsIndicators: false) {
                let allFilter = store.selectedSourceFilter == "all"
                let hasResults = !visibleSessions().isEmpty

                VStack(alignment: .leading, spacing: 18) {
                    MobileQuickFilters()
                    SidebarSearchField(text: $searchText)
                    if allFilter {
                        PinnedSection(sessions: pinnedSessions) { session in
                            sessionPendingDeletion = session
                        }
                        // One chronological list, newest activity first,
                        // every source mixed in; the per-chat icon tells
                        // the origin apart (CLI, Telegram, Mobile...).
                        SessionSourceSection(
                            title: "All sessions",
                            icon: "clock",
                            sessions: allSessionsChronological,
                            searchText: searchText,
                            onSessionSelected: onSessionSelected,
                            onDelete: { session in sessionPendingDeletion = session }
                        )
                    } else {
                        SessionSourceSection(
                            title: regularSectionTitle,
                            icon: regularSectionIcon,
                            sessions: visibleSessions(),
                            searchText: searchText,
                            onSessionSelected: onSessionSelected,
                            onDelete: { session in sessionPendingDeletion = session }
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
            SidebarFooter()
        }
        .background(HermesTheme.sidebar)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            try? await store.refreshSessions()
            try? await store.refreshCapabilities()
        }
        .sheet(isPresented: $showingArchived) {
            ArchivedSessionsView().environmentObject(store)
        }
        .alert("Delete this session?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let id = sessionPendingDeletion?.id {
                    Task { try? await store.deleteSession(id: id) }
                }
                sessionPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                sessionPendingDeletion = nil
            }
        } message: {
            Text("This permanently deletes the chat from your desktop. Use Archive instead if you want to keep it recoverable.")
        }
    }

    @State private var showingArchived = false
    @State private var sessionPendingDeletion: HermesSession?

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingDeletion != nil },
            set: { if !$0 { sessionPendingDeletion = nil } }
        )
    }

    private var selectedFilter: String { store.selectedSourceFilter.lowercased() }

    private var regularSectionTitle: String {
        SessionSource.displayName(selectedFilter)
    }

    private var regularSectionIcon: String {
        SessionSource.icon(selectedFilter)
    }

    private func visibleSessions(only source: String? = nil) -> [HermesSession] {
        store.sessions.filter { session in
            // Normalize the wire name: sessions created through the mobile
            // plugin/bridge read as "acp" from the DB (and used to be sent
            // as-is). Treat them as "mobile" everywhere, like the backend
            // now does, so filtering works against older dashboards too.
            let rawSource = (session.source ?? "desktop").lowercased()
            let sessionSource = rawSource == "acp" ? "mobile" : rawSource
            let selectedSource = store.selectedSourceFilter.lowercased()
            if selectedSource != "all", sessionSource != selectedSource { return false }
            if let source, sessionSource != source { return false }
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

    private var pinnedSessions: [HermesSession] {
        store.sessions.filter { $0.pinned == true }
    }

    /// All sources mixed, newest activity first. Pinned chats already
    /// appear in the pinned card on top, so they are not duplicated here.
    private var allSessionsChronological: [HermesSession] {
        visibleSessions()
            .filter { $0.pinned != true }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

private struct MobileSessionsHeader: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Binding var showingSettings: Bool
    let onNewSession: () -> Void
    let onOpenCommands: () -> Void
    let onOpenArchived: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: -2) {
                Text("HERMES")
                    .font(HermesTheme.brandSerif(size: 28))
                    .tracking(0.8)
                    .foregroundStyle(HermesTheme.ink)
                Text("AGENT")
                    .font(HermesTheme.brandSerif(size: 20))
                    .tracking(1.2)
                    .foregroundStyle(HermesTheme.ink.opacity(0.94))
            }
            .textCase(.uppercase)
            Spacer()
            Button(action: onNewSession) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HermesTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: onOpenCommands) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            Button(action: onOpenArchived) {
                Image(systemName: "archivebox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .frame(width: 32, height: 32)
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

}

private struct MobileQuickFilters: View {
    @ObservedObject private var theme = ThemeManager.shared
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
        SessionSource.displayName(source)
    }

    private func icon(for source: String) -> String {
        SessionSource.icon(source)
    }
}

/// Single source of truth for how a session source renders in the UI.
/// "acp" is the wire name for sessions created through the mobile
/// plugin/bridge; both it and "mobile" read as "Mobile" for the user.
enum SessionSource {
    static func displayName(_ source: String) -> String {
        switch source {
        case "all": "All"
        case "telegram": "Telegram"
        case "desktop": "Desktop"
        case "cli": "CLI"
        case "acp", "mobile": "Mobile"
        default: source.capitalized
        }
    }

    static func icon(_ source: String) -> String {
        switch source {
        case "telegram": "paperplane.circle.fill"
        case "desktop": "macwindow"
        case "cli": "terminal"
        case "acp", "mobile": "iphone"
        case "cron": "clock.arrow.circlepath"
        case "all": "checkerboard.rectangle"
        default: "bubble.left.and.bubble.right"
        }
    }
}

private struct SidebarSearchField: View {
    @ObservedObject private var theme = ThemeManager.shared
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
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    let sessions: [HermesSession]
    let onDelete: (HermesSession) -> Void

    var body: some View {
        if !sessions.isEmpty {
            SidebarSection(title: "Pinned", icon: "pin.fill") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sessions) { session in
                        Button {
                            Task {
                                await store.select(session: session)
                            }
                        } label: {
                            SidebarSessionRow(session: session, selected: session.id == store.selectedSessionID)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                Task { try? await store.pinSession(id: session.id, pinned: false) }
                            } label: {
                                Label("Unpin", systemImage: "pin.slash")
                            }
                            .tint(HermesTheme.ring)
                        }
                    }
                }
            }
        }
    }
}

private struct EmptySessionsState: View {
    @ObservedObject private var theme = ThemeManager.shared
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
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    let title: String
    let icon: String
    var accent: Color = HermesTheme.mutedForeground
    let sessions: [HermesSession]
    let searchText: String
    let onSessionSelected: () -> Void
    let onDelete: (HermesSession) -> Void

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
                        if group.title != "Today" || title.lowercased() == "telegram" || title.lowercased() == "all sessions" {
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        onDelete(session)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        Task { try? await store.archiveSession(id: session.id) }
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                    .tint(HermesTheme.warm)
                                    Button {
                                        Task { try? await store.pinSession(id: session.id, pinned: !(session.pinned ?? false)) }
                                    } label: {
                                        Label(session.pinned == true ? "Unpin" : "Pin", systemImage: session.pinned == true ? "pin.slash" : "pin")
                                    }
                                    .tint(HermesTheme.ring)
                                }
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
    @ObservedObject private var theme = ThemeManager.shared
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
            }
            .padding(.horizontal, 4)
            content
        }
    }
}

private struct SidebarGroupLabel: View {
    @ObservedObject private var theme = ThemeManager.shared
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
    @ObservedObject private var theme = ThemeManager.shared
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
            // Per-chat origin icon (CLI / Telegram / Mobile / Desktop),
            // always shown so rows align and the mixed chronological
            // "All sessions" list stays scannable.
            Image(systemName: SessionSource.icon(session.source ?? "desktop"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.55))
                .frame(width: 16)
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
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: HermesTheme.green)
            Text("Gateway ready")
            Text("·")
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.48))
            Image(systemName: "folder")
            Text(profileLabel)
            Spacer()
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

// MARK: - Archived sessions

private struct ArchivedSessionsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HermesMobileScreen(title: "Archived", subtitle: "chats hidden from the main list", icon: "archivebox", showsDone: true) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if store.archivedSessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 22))
                                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.4))
                            Text("Nothing archived")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HermesTheme.mutedForeground)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(store.archivedSessions) { session in
                            HStack(spacing: 10) {
                                Image(systemName: SessionSource.icon(session.source ?? "desktop"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.6))
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(HermesTheme.ink)
                                        .lineLimit(1)
                                    Text(session.subtitle)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(HermesTheme.mutedForeground)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Button {
                                    Task { try? await store.restoreSession(id: session.id) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Restore")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(HermesTheme.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable {
                await store.loadArchivedSessions()
            }
        }
        .task {
            await store.loadArchivedSessions()
        }
    }
}

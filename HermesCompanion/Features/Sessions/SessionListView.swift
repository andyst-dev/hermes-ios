import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingSettings: Bool
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            DesktopSidebarHeader()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    SidebarQuickActions()
                    SidebarSearchField(text: $searchText)
                    PinnedSection()
                    SessionSourceSection(
                        title: "Sessions",
                        icon: "checkerboard.rectangle",
                        sessions: visibleSessions(excluding: "telegram"),
                        searchText: searchText
                    )
                    SessionSourceSection(
                        title: "Telegram",
                        icon: "paperplane.circle.fill",
                        accent: Color(red: 0.180, green: 0.620, blue: 0.920),
                        sessions: visibleSessions(only: "telegram"),
                        searchText: searchText
                    )
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

    private func visibleSessions(only source: String? = nil, excluding excludedSource: String? = nil) -> [HermesSession] {
        store.sessions.filter { session in
            let sessionSource = (session.source ?? "desktop").lowercased()
            if let source, sessionSource != source { return false }
            if let excludedSource, sessionSource == excludedSource { return false }
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            let needle = searchText.lowercased()
            return session.title.lowercased().contains(needle) || session.subtitle.lowercased().contains(needle)
        }
    }
}

private struct DesktopSidebarHeader: View {
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Color(red: 1.0, green: 0.31, blue: 0.32)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 1.0, green: 0.80, blue: 0.25)).frame(width: 12, height: 12)
            Circle().fill(Color(red: 0.38, green: 0.82, blue: 0.40)).frame(width: 12, height: 12)
            Image(systemName: "sidebar.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HermesTheme.mutedForeground)
                .padding(.leading, 4)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HermesTheme.mutedForeground)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

private struct SidebarQuickActions: View {
    private let actions: [(String, String, String?)] = [
        ("New session", "cylinder.split.1x2", "⌘  N"),
        ("Capabilities", "shippingbox", nil),
        ("Messaging", "bubble.left", nil),
        ("Artifacts", "doc", nil)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(actions, id: \.0) { action in
                HStack(spacing: 11) {
                    Image(systemName: action.1)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(HermesTheme.mutedForeground)
                    Text(action.0)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(HermesTheme.ink.opacity(0.82))
                    Spacer()
                    if let shortcut = action.2 {
                        Text(shortcut)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
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

private struct SessionSourceSection: View {
    @EnvironmentObject private var store: AppStore
    let title: String
    let icon: String
    var accent: Color = HermesTheme.mutedForeground
    let sessions: [HermesSession]
    let searchText: String

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
                                SidebarSessionRow(session: session, selected: session.id == store.selectedSessionID)
                                    .onTapGesture { Task { await store.select(session: session) } }
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                footerIcon("house", selected: true)
                footerIcon("plus", selected: false)
                Spacer()
                Button { showingSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HermesTheme.mutedForeground)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Image(systemName: "command")
                Image(systemName: "waveform.path.ecg")
                Text("Gateway ready")
                Spacer()
                Image(systemName: "folder")
                Text(profileLabel)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(HermesTheme.mutedForeground.opacity(0.82))
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(HermesTheme.sidebar.opacity(0.98))
    }

    private var profileLabel: String {
        if case .connected(let host) = store.connection { return host.profile }
        return "default"
    }

    private func footerIcon(_ systemName: String, selected: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? HermesTheme.primary : HermesTheme.mutedForeground)
            .frame(width: 28, height: 28)
            .background(selected ? HermesTheme.userBubble : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(selected ? HermesTheme.userBubbleBorder : Color.clear, lineWidth: 1))
    }
}

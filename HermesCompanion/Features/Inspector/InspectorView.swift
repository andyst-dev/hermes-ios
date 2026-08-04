import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var showingArchiveAlert = false
    @State private var actionMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HermesMobileSection(title: "Session", icon: "message", accent: HermesTheme.primary) {
                    if let session = store.selectedSession {
                        HermesMobileRow(title: "Title", subtitle: session.title, icon: "text.alignleft", accent: HermesTheme.mutedForeground)
                        HermesMobileRow(title: "Source", subtitle: session.source ?? "desktop", icon: "macwindow", accent: HermesTheme.primary)
                        HermesMobileRow(title: "Status", subtitle: session.status.rawValue, icon: statusIcon(session.status), accent: statusColor(session.status))
                        HermesMobileRow(title: "Messages", subtitle: "\(store.messages.count) in view", icon: "bubble.left.and.bubble.right", accent: HermesTheme.mutedForeground)
                        HermesMobileRow(title: "Updated", subtitle: relativeTime(session.updatedAt), icon: "clock", accent: HermesTheme.mutedForeground)
                    } else {
                        EmptyLine("No conversation selected")
                    }
                }

                HermesMobileSection(title: "Tools used here", icon: "wrench.and.screwdriver", accent: HermesTheme.mutedForeground) {
                    let tools = usedTools
                    if tools.isEmpty {
                        EmptyLine("No tool calls in this conversation")
                    } else {
                        ForEach(tools, id: \.name) { tool in
                            HermesMobileRow(
                                title: tool.name,
                                subtitle: "\(tool.count) call\(tool.count == 1 ? "" : "s")",
                                icon: "terminal",
                                accent: accent(for: tool.state)
                            )
                        }
                    }
                }

                if store.selectedSession != nil {
                    HermesMobileSection(title: "Actions", icon: "bolt.fill", accent: HermesTheme.primary) {
                        SettingsButtonRow(title: "Rename conversation", subtitle: "Change the title on Desktop", icon: "pencil", accent: HermesTheme.primary) {
                            renameText = store.selectedSession?.title ?? ""
                            showingRenameAlert = true
                        }
                        SettingsButtonRow(title: "Archive conversation", subtitle: "Hide from the list (Desktop keeps it)", icon: "archivebox", accent: HermesTheme.warm) {
                            showingArchiveAlert = true
                        }
                    }

                    if let actionMessage {
                        Text(actionMessage)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .padding(.horizontal, 3)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(HermesTheme.sidebar.ignoresSafeArea())
        .alert("Rename conversation", isPresented: $showingRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, let session = store.selectedSession else { return }
                Task {
                    do {
                        try await store.renameSession(id: session.id, title: title)
                        actionMessage = "Renamed."
                    } catch {
                        actionMessage = "Rename failed."
                    }
                }
            }
        }
        .alert("Archive this conversation?", isPresented: $showingArchiveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Archive", role: .destructive) {
                guard let session = store.selectedSession else { return }
                Task {
                    try? await store.archiveSession(id: session.id)
                    dismiss()
                }
            }
        } message: {
            Text("It stays on Desktop, just hidden from this list.")
        }
    }

    private var usedTools: [ToolUsage] {
        var counts: [String: Int] = [:]
        var state: [String: HermesToolCall.Status] = [:]
        for message in store.messages {
            for call in message.toolCalls {
                counts[call.name, default: 0] += 1
                state[call.name] = call.status
            }
        }
        return counts.map { ToolUsage(name: $0.key, count: $0.value, state: state[$0.key] ?? .succeeded) }
            .sorted { $0.count > $1.count }
    }

    private func statusIcon(_ status: HermesSession.SessionStatus) -> String {
        switch status {
        case .running: "play.fill"
        case .waitingApproval: "hand.raised.fill"
        case .failed: "xmark"
        case .completed: "checkmark"
        case .idle: "pause"
        }
    }

    private func statusColor(_ status: HermesSession.SessionStatus) -> Color {
        switch status {
        case .running: HermesTheme.ring
        case .waitingApproval: HermesTheme.primary
        case .failed: HermesTheme.destructive
        case .completed: HermesTheme.green
        case .idle: HermesTheme.mutedForeground
        }
    }

    private func accent(for state: HermesToolCall.Status) -> Color {
        switch state {
        case .failed: HermesTheme.destructive
        case .running: HermesTheme.ring
        case .waitingApproval: HermesTheme.primary
        case .succeeded: HermesTheme.green
        case .queued: HermesTheme.mutedForeground
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct ToolUsage: Identifiable {
    var id: String { name }
    let name: String
    let count: Int
    let state: HermesToolCall.Status
}

struct CapabilityBadges: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HermesTheme.foreground.opacity(0.84))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(HermesTheme.background.opacity(0.34), in: Capsule())
            }
        }
        .padding(.horizontal, 4)
    }
}

struct EmptyLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(HermesTheme.mutedForeground).padding(.horizontal, 10) }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 280
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

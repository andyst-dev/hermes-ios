import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSection(title: "Model", icon: "cpu") {
                    Picker("Model", selection: Binding(get: { store.activeModelID ?? "" }, set: { store.activeModelID = $0 })) {
                        ForEach(store.capabilities.models) { model in
                            Text("\(model.displayName) · \(model.provider)").tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    if let model = store.activeModel {
                        CapabilityBadges(items: [model.supportsTools ? "tools" : "no tools", model.supportsVision ? "vision" : "text"])
                    }
                }

                InspectorSection(title: "Approvals", icon: "hand.raised.fill") {
                    if store.capabilities.approvals.isEmpty {
                        EmptyLine("No pending approvals")
                    } else {
                        ForEach(store.capabilities.approvals) { approval in
                            RowCard(title: approval.title, subtitle: approval.detail, accent: riskColor(approval.risk), icon: "exclamationmark.shield")
                        }
                    }
                }

                InspectorSection(title: "Jobs", icon: "bolt.horizontal.circle") {
                    ForEach(store.capabilities.jobs) { job in
                        RowCard(title: job.title, subtitle: job.detail, accent: statusColor(job.status), icon: jobIcon(job.status))
                    }
                }

                InspectorSection(title: "Files", icon: "folder") {
                    ForEach(store.capabilities.files) { file in
                        RowCard(title: file.label, subtitle: store.privacyMode ? redactedPath(file.path) : file.path, accent: HermesTheme.ring, icon: fileIcon(file.kind))
                    }
                }

                InspectorSection(title: "Tools", icon: "wrench.and.screwdriver") {
                    CapabilityBadges(items: store.capabilities.tools)
                }
            }
            .padding(14)
        }
        .background(HermesTheme.sidebar)
    }

    private func riskColor(_ risk: HermesApproval.Risk) -> Color {
        switch risk {
        case .low: HermesTheme.green
        case .medium: HermesTheme.ring
        case .high: HermesTheme.destructive
        }
    }

    private func statusColor(_ status: HermesJob.Status) -> Color {
        switch status {
        case .running: HermesTheme.ring
        case .waitingApproval: HermesTheme.primary
        case .completed: HermesTheme.green
        case .failed: HermesTheme.destructive
        case .scheduled: HermesTheme.mutedForeground
        }
    }

    private func jobIcon(_ status: HermesJob.Status) -> String {
        switch status {
        case .running: "play.fill"
        case .waitingApproval: "hand.raised.fill"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .scheduled: "calendar"
        }
    }

    private func fileIcon(_ kind: HermesFileArtifact.Kind) -> String {
        switch kind {
        case .text: "doc.text"
        case .image: "photo"
        case .html: "safari"
        case .pdf: "doc.richtext"
        case .directory: "folder"
        }
    }

    private func redactedPath(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? "file"
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(HermesTheme.ring)
                .textCase(.uppercase)
            content
        }
        .padding(12)
        .desktopPanel(cornerRadius: 18)
    }
}

struct RowCard: View {
    let title: String
    let subtitle: String
    let accent: Color
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HermesTheme.foreground)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(HermesTheme.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(HermesTheme.muted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HermesTheme.border, lineWidth: 1))
    }
}

struct CapabilityBadges: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HermesTheme.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(HermesTheme.secondary, in: Capsule())
                    .overlay(Capsule().stroke(HermesTheme.border, lineWidth: 1))
            }
        }
    }
}

struct EmptyLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(HermesTheme.mutedForeground) }
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

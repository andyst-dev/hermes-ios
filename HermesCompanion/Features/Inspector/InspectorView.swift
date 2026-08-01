import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HermesMobileSection(title: "Model", icon: "cpu", accent: HermesTheme.primary) {
                    if let model = store.activeModel {
                        HermesMobileRow(
                            title: model.displayName,
                            subtitle: "\(model.providerName ?? model.provider) · \(model.supportsTools ? "tools" : "text") · \(model.supportsVision ? "vision" : "no vision")",
                            icon: "cpu",
                            accent: HermesTheme.primary,
                            selected: true
                        )
                    }
                    CapabilityBadges(items: store.capabilities.models.prefix(5).map { $0.displayName })
                }

                HermesMobileSection(title: "Approvals", icon: "hand.raised.fill", accent: HermesTheme.warm) {
                    if store.capabilities.approvals.isEmpty {
                        EmptyLine("No pending approvals")
                    } else {
                        ForEach(store.capabilities.approvals) { approval in
                            HermesMobileRow(title: approval.title, subtitle: approval.detail, icon: "exclamationmark.shield", accent: riskColor(approval.risk))
                        }
                    }
                }

                HermesMobileSection(title: "Jobs", icon: "bolt.horizontal.circle", accent: HermesTheme.primary) {
                    ForEach(store.capabilities.jobs) { job in
                        HermesMobileRow(title: job.title, subtitle: job.detail, icon: jobIcon(job.status), accent: statusColor(job.status))
                    }
                }

                HermesMobileSection(title: "Files", icon: "folder", accent: HermesTheme.mutedForeground) {
                    ForEach(store.capabilities.files) { file in
                        HermesMobileRow(title: file.label, subtitle: store.privacyMode ? redactedPath(file.path) : file.path, icon: fileIcon(file.kind), accent: HermesTheme.primary)
                    }
                }

                HermesMobileSection(title: "Tools", icon: "wrench.and.screwdriver", accent: HermesTheme.mutedForeground) {
                    CapabilityBadges(items: store.capabilities.tools)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(HermesTheme.sidebar.ignoresSafeArea())
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

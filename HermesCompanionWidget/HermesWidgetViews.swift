import SwiftUI
import WidgetKit

// MARK: - Home screen overview (small / medium / large)

struct HermesOverviewView: View {
    let entry: HermesEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 0) {
            statusBar(s)
            switch family {
            case .systemSmall:
                smallBody(s)
            case .systemLarge:
                largeBody(s)
            default:
                mediumBody(s)
            }
        }
        .padding(.top, 2)
        .widgetURL(sessionURL(s))
    }

    // Compact status line replaces the old heavy brand header, so the
    // content starts right at the top with no dead space.
    private func statusBar(_ s: HermesWidgetSnapshot) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(s.gatewayStatus))
                .frame(width: 6, height: 6)
            Text(s.gatewayStatus.label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text("HERMES")
                .font(.system(size: 7.5, weight: .heavy, design: .serif))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.bottom, 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 7.5, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(.white.opacity(0.35))
    }

    private func smallBody(_ s: HermesWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Session")
            if s.sessionID.isEmpty {
                Text("No active session")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 2)
            } else {
                Text(s.sessionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            Spacer(minLength: 6)
            if let next = s.nextCronDate, !s.nextCronTitle.isEmpty {
                sectionLabel("Cron")
                Text("\(s.nextCronTitle)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.top, 2)
                Text(HermesOverviewView.relativeTime(from: next))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediumBody(_ s: HermesWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Session")
                    activeSession(s, compact: true)
                    secondSessionRow(s, font: 11)
                }
                Spacer(minLength: 8)
                if !s.sessionID.isEmpty {
                    Link(destination: URL(string: "hermes://session/\(s.sessionID)")!) {
                        Text("Open")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.9), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 6)
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 6)
            HStack(spacing: 6) {
                if let next = s.nextCronDate, !s.nextCronTitle.isEmpty {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Next: \(s.nextCronTitle) · \(HermesOverviewView.relativeTime(from: next))")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                Link(destination: URL(string: "hermes://new-chat")!) {
                    Text("New chat")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.9), in: Capsule())
                }
            }
        }
    }

    private func largeBody(_ s: HermesWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Session")
            if s.sessionID.isEmpty {
                Text("No active session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 3)
            } else {
                Text(s.sessionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.top, 3)
                if !s.lastMessagePreview.isEmpty {
                    Text(s.lastMessagePreview)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                        .padding(.top, 3)
                }
                secondSessionRow(s, font: 12.5)
            }
            Spacer(minLength: 8)
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 6)
            if let next = s.nextCronDate, !s.nextCronTitle.isEmpty {
                sectionLabel("Cron")
                Text("\(s.nextCronTitle)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.top, 3)
                Text(HermesOverviewView.relativeTime(from: next))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 1)
            }
            Spacer(minLength: 6)
            HStack {
                if s.updatedAt > Date().addingTimeInterval(-7 * 86400) {
                    Text("Updated \(HermesOverviewView.relativeTime(from: s.updatedAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    Text("—")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Link(destination: URL(string: "hermes://new-chat")!) {
                    Text("New chat")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.9), in: Capsule())
                }
            }
        }
    }

    /// Second recent conversation, shown on medium/large families where the
    /// SESSION block has room for more than one row. Nil when there is only
    /// one conversation (or none).
    @ViewBuilder
    private func secondSessionRow(_ s: HermesWidgetSnapshot, font: CGFloat = 12) -> some View {
        if let t2 = s.session2Title {
            VStack(alignment: .leading, spacing: 1) {
                Text(t2)
                    .font(.system(size: font, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let sub = s.session2Subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: font - 1.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .padding(.top, 5)
        }
    }

    private func activeSession(_ s: HermesWidgetSnapshot, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if s.sessionID.isEmpty {
                Text("No active session")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text(s.sessionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if compact, !s.lastMessagePreview.isEmpty {
                    Text(s.lastMessagePreview)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                } else if !s.sessionSubtitle.isEmpty {
                    Text(s.sessionSubtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusColor(_ status: HermesWidgetSnapshot.GatewayStatus) -> Color {
        let parts = status.color.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return .gray }
        return Color(red: parts[0], green: parts[1], blue: parts[2])
    }

    private func sessionURL(_ s: HermesWidgetSnapshot) -> URL? {
        s.sessionID.isEmpty ? URL(string: "hermes://new-chat") : URL(string: "hermes://session/\(s.sessionID)")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relativeTime(from date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - Lock screen

struct HermesLockViews: View {
    let entry: HermesEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        default:
            inline
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusShort)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("HERMES", systemImage: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            if let next = entry.snapshot.nextCronDate, !entry.snapshot.nextCronTitle.isEmpty {
                Text("Next: \(entry.snapshot.nextCronTitle) · \(HermesOverviewView.relativeTime(from: next))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label("\(statusLabel)", systemImage: "bolt.fill")
    }

    private var statusLabel: String {
        entry.snapshot.gatewayStatus.label
    }

    private var statusShort: String {
        switch entry.snapshot.gatewayStatus {
        case .up: "ON"
        case .approval: "APP"
        case .down: "OFF"
        }
    }

    private var statusColor: Color {
        let parts = entry.snapshot.gatewayStatus.color.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return .gray }
        return Color(red: parts[0], green: parts[1], blue: parts[2])
    }
}

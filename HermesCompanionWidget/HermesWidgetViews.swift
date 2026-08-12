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
            let titles = sessionTitles(s, upTo: 2)
            if titles.isEmpty {
                noSessionRow(font: 11)
            } else {
                sessionTitleRow(titles[0], font: 12)
                if titles.count > 1 { sessionTitleRow(titles[1], font: 11, dim: true) }
            }
            Spacer(minLength: 6)
            if let first = cronRows(s, upTo: 1).first {
                sectionLabel("Cron")
                cronTitleRow(first.0, font: 10.5)
                cronTimeRow(first.1, font: 9.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediumBody(_ s: HermesWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Session")
            let titles = sessionTitles(s, upTo: 2)
            if titles.isEmpty {
                noSessionRow(font: 12.5)
            } else {
                sessionTitleRow(titles[0], font: 13)
                if titles.count > 1 { sessionTitleRow(titles[1], font: 12, dim: true) }
            }
            Spacer(minLength: 6)
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 6)
            HStack(spacing: 6) {
                if let first = cronRows(s, upTo: 1).first {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Next: \(first.0) · \(HermesOverviewView.relativeTime(from: first.1 ?? .now))")
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
            let titles = sessionTitles(s, upTo: 3)
            if titles.isEmpty {
                noSessionRow(font: 13)
            } else {
                sessionTitleRow(titles[0], font: 15)
                if titles.count > 1 { sessionTitleRow(titles[1], font: 13.5, dim: true) }
                if titles.count > 2 { sessionTitleRow(titles[2], font: 13.5, dim: true) }
            }
            Spacer(minLength: 8)
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 6)
            let crons = cronRows(s, upTo: 3)
            if !crons.isEmpty {
                sectionLabel("Cron")
                ForEach(Array(crons.enumerated()), id: \.offset) { _, cron in
                    HStack {
                        Text(cron.0)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(HermesOverviewView.relativeTime(from: cron.1 ?? .now))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.top, 3)
                }
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

    private func sessionTitles(_ s: HermesWidgetSnapshot, upTo max: Int) -> [String] {
        var out: [String] = []
        if !s.sessionTitle.isEmpty { out.append(s.sessionTitle) }
        if let t = s.session2Title { out.append(t) }
        if let t = s.session3Title { out.append(t) }
        return Array(out.prefix(max))
    }

    private func cronRows(_ s: HermesWidgetSnapshot, upTo max: Int) -> [(String, Date?)] {
        if let list = s.cronList {
            return Array(list.prefix(max)).map { ($0.title, $0.date) }
        }
        if !s.nextCronTitle.isEmpty {
            return [(s.nextCronTitle, s.nextCronDate)]
        }
        return []
    }

    private func sessionTitleRow(_ title: String, font: CGFloat, dim: Bool = false) -> some View {
        Text(title)
            .font(.system(size: font, weight: .semibold))
            .foregroundStyle(dim ? .white.opacity(0.85) : .white)
            .lineLimit(1)
            .padding(.top, 3)
    }

    private func noSessionRow(font: CGFloat) -> some View {
        Text("No active session")
            .font(.system(size: font, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.top, 3)
    }

    private func cronTitleRow(_ title: String, font: CGFloat) -> some View {
        Text(title)
            .font(.system(size: font, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
            .padding(.top, 3)
    }

    private func cronTimeRow(_ date: Date?, font: CGFloat) -> some View {
        Text(HermesOverviewView.relativeTime(from: date ?? .now))
            .font(.system(size: font))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.top, 1)
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

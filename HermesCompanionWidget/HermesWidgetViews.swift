import SwiftUI
import WidgetKit

// MARK: - Medium overview

struct HermesOverviewView: View {
    let entry: HermesEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 0) {
            header(snapshot)
            Spacer(minLength: 4)
            activeSession(snapshot)
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 7)
            nextCron(snapshot)
        }
        .widgetURL(sessionURL(snapshot))
    }

    private func header(_ s: HermesWidgetSnapshot) -> some View {
        HStack(spacing: 6) {
            Text("HERMES")
                .font(.system(size: 10, weight: .heavy, design: .serif))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.9))
            Text("AGENT")
                .font(.system(size: 8, weight: .heavy, design: .serif))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Circle()
                .fill(statusColor(s.gatewayStatus))
                .frame(width: 6, height: 6)
            Text(s.gatewayStatus.label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func activeSession(_ s: HermesWidgetSnapshot) -> some View {
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
                if !s.sessionSubtitle.isEmpty {
                    Text(s.sessionSubtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                if !s.lastMessagePreview.isEmpty {
                    Text(s.lastMessagePreview)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextCron(_ s: HermesWidgetSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            if let next = s.nextCronDate, !s.nextCronTitle.isEmpty {
                Text("Next: \(s.nextCronTitle) · \(HermesOverviewView.relativeTime(from: next))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            } else {
                Text("No cron scheduled")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
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

import Foundation

/// Snapshot of the app state that the widget renders. Written by the app
/// into the shared App Group container whenever state changes or the
/// foreground refresh loop ticks; read by the widget extension to build
/// its timeline. No push involved — iOS refreshes the widget on its own
/// schedule.
struct HermesWidgetCron: Codable {
    var title: String
    var date: Date
}

struct HermesWidgetSnapshot: Codable {
    var gatewayUp = false
    var sessionID = ""
    var sessionTitle = ""
    var sessionSubtitle = ""
    var lastMessagePreview = ""
    var session2ID: String? = nil
    var session2Title: String? = nil
    var session2Subtitle: String? = nil
    var session3ID: String? = nil
    var session3Title: String? = nil
    var nextCronTitle = ""
    var nextCronDate: Date?
    var cronList: [HermesWidgetCron]? = nil
    var pendingApprovalCommand = ""
    var updatedAt = Date.distantPast

    static let appGroupID = "group.dev.hermes.companion"
    static let defaultsKey = "widget.snapshot.v1"

    var gatewayStatus: GatewayStatus {
        if !gatewayUp { return .down }
        if !pendingApprovalCommand.isEmpty { return .approval }
        return .up
    }

    enum GatewayStatus {
        case up, approval, down

        var label: String {
            switch self {
            case .up: "Gateway ready"
            case .approval: "Approval waiting"
            case .down: "Offline"
            }
        }

        var color: String {
            switch self {
            case .up: "0.38,0.85,0.55"      // green
            case .approval: "0.95,0.72,0.32" // warm
            case .down: "0.90,0.35,0.35"     // red
            }
        }
    }

    static func read() -> HermesWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(HermesWidgetSnapshot.self, from: data)
        else { return HermesWidgetSnapshot() }
        return snapshot
    }

    func write() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

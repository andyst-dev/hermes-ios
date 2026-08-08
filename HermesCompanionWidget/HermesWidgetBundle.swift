import WidgetKit
import SwiftUI

@main
struct HermesWidgetBundle: WidgetBundle {
    var body: some Widget {
        HermesOverviewWidget()
        HermesLockScreenWidget()
    }
}

// MARK: - Home screen overview

struct HermesOverviewWidget: Widget {
    let kind = "HermesOverview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermesTimelineProvider()) { entry in
            HermesOverviewView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.10, blue: 0.13), Color(red: 0.14, green: 0.12, blue: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Hermes")
        .description("Gateway status, active session and next cron run.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Lock screen complications

struct HermesLockScreenWidget: Widget {
    let kind = "HermesLock"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermesTimelineProvider()) { entry in
            HermesLockViews(entry: entry)
        }
        .configurationDisplayName("Hermes status")
        .description("Gateway status and next cron run.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

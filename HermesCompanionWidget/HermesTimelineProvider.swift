import WidgetKit

struct HermesEntry: TimelineEntry {
    let date: Date
    let snapshot: HermesWidgetSnapshot

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: snapshot.pendingApprovalCommand.isEmpty ? 0 : 100)
    }
}

struct HermesTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HermesEntry {
        HermesEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (HermesEntry) -> Void) {
        completion(HermesEntry(date: .now, snapshot: .read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HermesEntry>) -> Void) {
        let snapshot = HermesWidgetSnapshot.read()
        let now = Date()
        // If the app wrote a snapshot recently, refresh often (the user is
        // actively using Hermes); otherwise fall back to iOS's slower budget.
        let freshness = now.timeIntervalSince(snapshot.updatedAt)
        let refreshMinutes: TimeInterval = freshness < 10 * 60 ? 15 : 60
        let timeline = Timeline(
            entries: [HermesEntry(date: now, snapshot: snapshot)],
            policy: .after(now.addingTimeInterval(refreshMinutes * 60))
        )
        completion(timeline)
    }
}

extension HermesWidgetSnapshot {
    /// Static demo data shown while iOS previews the widget in the gallery.
    static let preview = HermesWidgetSnapshot(
        gatewayUp: true,
        sessionID: "preview",
        sessionTitle: "Lier iPhone sans Tailscale",
        sessionSubtitle: "408 messages · Telegram",
        lastMessagePreview: "Le tunnel est actif, tu peux scanner le QR…",
        nextCronTitle: "Daily briefing",
        nextCronDate: Date().addingTimeInterval(2 * 3600),
        pendingApprovalCommand: "",
        updatedAt: .now
    )
}

import BackgroundTasks
import UserNotifications

/// Local-notification alerts without an APNs account.
///
/// The app registers a Background App Refresh task that polls
/// `/notifications/pending` on the desktop backend; when an approval is
/// waiting for a phone verdict or a cron job just finished, a LOCAL
/// notification is fired. iOS schedules the refresh opportunistically (a few
/// times an hour) — this is not instant push, but it needs no Apple
/// Developer paid account, no APNs key and no server.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()
    static let backgroundTaskID = "dev.hermes.companion.pending"

    private var lastAlertedApprovalIDs: Set<String> = []
    private var lastAlertedCronKeys: Set<String> = []

    // MARK: - Registration

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskID, using: nil) { task in
            Task { @MainActor in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                await self.runBackgroundCheck(task: refreshTask)
            }
        }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("HERMES: notifications granted=\(granted) error=\(error?.localizedDescription ?? "none")")
        }
    }

    func scheduleBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // earliest: 15 min
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Background check

    func runBackgroundCheck(task: BGAppRefreshTask) async {
        scheduleBackgroundCheck()  // chain the next refresh window
        task.expirationHandler = {
            print("HERMES: background check expired")
        }
        do {
            guard let client = await makeBackgroundClient() else {
                task.setTaskCompleted(success: true)
                return
            }
            let pending = try await client.pendingNotifications()
            fireNotifications(for: pending)
            task.setTaskCompleted(success: true)
        } catch {
            print("HERMES: background check failed: \(error.localizedDescription)")
            task.setTaskCompleted(success: false)
        }
    }

    /// Foreground poll — runs right after connect so an approval that arrived
    /// while the app was closed is surfaced immediately.
    @discardableResult
    func checkInForeground(using client: HermesClient) async -> HermesPendingApproval? {
        guard let pending = try? await client.pendingNotifications() else { return nil }
        fireNotifications(for: pending)
        return pending.approvals.first
    }

    // MARK: - Alerting

    private func fireNotifications(for pending: HermesPendingNotifications) {
        let center = UNUserNotificationCenter.current()
        let now = Date()

        for approval in pending.approvals where !lastAlertedApprovalIDs.contains(approval.id) {
            lastAlertedApprovalIDs.insert(approval.id)
            trim(&lastAlertedApprovalIDs)
            let content = UNMutableNotificationContent()
            content.title = "Command needs approval"
            content.body = approval.command
            content.sound = .default
            content.userInfo = ["approvalID": approval.id, "sessionID": approval.sessionID]
            center.add(UNNotificationRequest(identifier: "approval-\(approval.id)", content: content, trigger: nil))
        }

        for run in pending.recentCron where run.isFinished {
            guard isRecent(run.finishedAt ?? run.claimedAt, now: now) else { continue }
            let key = run.id
            guard !lastAlertedCronKeys.contains(key) else { continue }
            lastAlertedCronKeys.insert(key)
            trim(&lastAlertedCronKeys)
            let content = UNMutableNotificationContent()
            content.title = run.status == "completed" ? "Cron job finished" : "Cron job failed"
            content.body = run.summary ?? "Job \(run.jobID) \(run.status)"
            content.sound = .default
            content.userInfo = ["jobID": run.jobID]
            center.add(UNNotificationRequest(identifier: "cron-\(key)", content: content, trigger: nil))
        }
    }

    private func makeBackgroundClient() async -> HermesClient? {
        guard let hostString = UserDefaults.standard.string(forKey: "hermes.host"),
              let hostURL = URL(string: hostString) else { return nil }
        let profile = UserDefaults.standard.string(forKey: "hermes.profile") ?? "default"
        let transport: any HermesTransport = HTTPHermesTransport(tokenProvider: {
            KeychainStore.loadToken()
        })
        let client = HermesClient(transport: transport)
        let host = HermesHost(name: "Desktop Hermes", baseURL: hostURL, profile: profile)
        // connect() resolves the base URL and verifies reachability in one call.
        guard (try? await client.connect(host: host)) != nil else { return nil }
        return client
    }

    private func isRecent(_ iso: String?, now: Date) -> Bool {
        guard let iso, let date = Self.isoDate(iso) else { return false }
        return now.timeIntervalSince(date) < 30 * 60  // finished within the last 30 min
    }

    private func trim(_ set: inout Set<String>) {
        if set.count > 200 {
            set.removeAll(keepingCapacity: true)
        }
    }

    private nonisolated(unsafe) static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let isoStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func isoDate(_ raw: String) -> Date? {
        isoFractional.date(from: raw) ?? isoStandard.date(from: raw)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show alerts even while the app is foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

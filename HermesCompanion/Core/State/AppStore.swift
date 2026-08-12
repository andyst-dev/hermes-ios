import Foundation
import LocalAuthentication

@MainActor
final class AppStore: ObservableObject {
    @Published var connection: HermesConnectionState = .disconnected
    @Published var sessions: [HermesSession] = []
    /// Archived chats (hidden from the main list), shown in the archive sheet.
    @Published var archivedSessions: [HermesSession] = []
    @Published var selectedSessionID: String?
    @Published var messages: [HermesMessage] = []
    @Published var composerText: String = ""
    @Published var isStreaming = false
    @Published var capabilities = PreviewData.capabilities
    @Published var activeModelID = PreviewData.capabilities.models.first?.id
    @Published var activeProviderID = PreviewData.capabilities.models.first?.provider
    @Published var selectedSourceFilter: String = "all"
    @Published var privacyMode = true
    @Published var pendingAttachments: [OutboundPrompt.Attachment] = []
    @Published var pendingApproval: ApprovalRequest?
    @Published var reasoningEffort = HermesReasoningEffort(effort: "medium", options: HermesReasoningEffort.defaultOptions)
    @Published var tunnelStatus = HermesTunnelStatus(ok: true, active: false, provider: "", publicUrl: "", localUrl: "", error: "")
    @Published var cronJobs: [HermesCronJob] = []
    @Published var cronUnavailable = false
    @Published var skills: [HermesSkill] = []
    @Published var memory = HermesMemory(ok: true, memory: [], user: [])

    private let client: HermesClient
    /// Foreground auto-refresh loop (30 s): keeps sessions, cron, memory and
    /// pending approvals live without push. Suspended while a chat streams.
    @Published var isAppActive = true
    private var autoRefreshTask: Task<Void, Never>?
    /// High-frequency poll used only while ChatView is visible. Mobile turns
    /// still use their existing SSE stream; this task only mirrors turns
    /// started by another Hermes surface.
    private var liveDraftTask: Task<Void, Never>?
    private var liveDraftPollGeneration = 0
    private var liveDraftSessionID: String?
    private var liveDraftMessageID: String?
    private var liveDraftSequence = -1
    private var liveDraftCompletedSequence: Int?
    private var liveDraftIsActive = false
    /// Set by a widget deep link (hermes://session/… or hermes://new-chat);
    /// MainShellView watches it to bring up the chat.
    @Published var deepLinkSessionID: String?

    // MARK: - Face ID / passcode lock

    @Published var isLocked = false
    @Published var faceIDUnlockError: String?

    init(client: HermesClient) {
        self.client = client
        configureLockIfNeeded()
    }

    /// Locks the app on launch when the Face ID toggle is on. If neither
    /// biometrics nor a device passcode is available, the lock would be a
    /// dead end, so the toggle is turned off instead.
    func configureLockIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "hermes.faceidLock") else { return }
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            isLocked = true
        } else {
            UserDefaults.standard.set(false, forKey: "hermes.faceidLock")
        }
    }

    func lockNow() {
        guard UserDefaults.standard.bool(forKey: "hermes.faceidLock") else { return }
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            isLocked = true
        }
    }

    /// Prompts for Face ID (or the device passcode) and unlocks on success.
    func unlockWithFaceID() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            faceIDUnlockError = error?.localizedDescription ?? "Biometrics are not available on this device."
            return
        }
        do {
            let granted = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Hermes Companion"
            )
            if granted {
                isLocked = false
                faceIDUnlockError = nil
            }
        } catch {
            faceIDUnlockError = error.localizedDescription
        }
    }

    var selectedSession: HermesSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    var activeModel: HermesModel? {
        capabilities.models.first { $0.id == activeModelID && ($0.provider == activeProviderID || activeProviderID == nil) }
    }

    var availableSources: [String] {
        let sources = Set(sessions.compactMap { $0.source?.lowercased() }.filter { !$0.isEmpty })
        return ["all"] + sources.sorted()
    }

    var filteredSessions: [HermesSession] {
        guard selectedSourceFilter != "all" else { return sessions }
        return sessions.filter { ($0.source ?? "").lowercased() == selectedSourceFilter }
    }

    func connect(host: HermesHost) async {
        connection = .connecting
        do {
            let connectedHost = try await client.connect(host: host)
            connection = .connected(connectedHost)
            try await refreshSessions()
            try await refreshCapabilities()
            await refreshReasoningEffort()
            await checkPendingApprovals()
            await refreshCron()
            startAutoRefresh()
            writeWidgetSnapshot()
            consumePendingOpenSession()
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    /// Opens the conversation requested by the "Open a Hermes session" Siri
    /// intent (it writes the target id before launching the app).
    private func consumePendingOpenSession() {
        let key = "hermes.pendingOpenSessionID"
        guard let pendingID = UserDefaults.standard.string(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        guard sessions.contains(where: { $0.id == pendingID }) else { return }
        selectedSessionID = pendingID
    }

    /// Foreground alert poll — surfaces an approval that arrived while the
    /// app was closed (and keeps the local-notification dedup state warm).
    func checkPendingApprovals() async {
        guard case .connected = connection else { return }
        if let approval = await NotificationManager.shared.checkInForeground(using: client) {
            pendingApproval = ApprovalRequest(id: approval.id, command: approval.command, description: approval.command)
        } else {
            // The desktop approval is gone (approved / denied / expired) —
            // clear the stale state so the widget and the approval card
            // don't keep showing "Approval waiting" forever.
            pendingApproval = nil
        }
    }

    func refreshSessions() async throws {
        sessions = try await client.sessions()
        if selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }
        if let selectedSessionID {
            messages = try await client.messages(sessionID: selectedSessionID)
        }
    }

    func refreshCapabilities() async throws {
        // Model discovery is independent from the lightweight capability snapshot.
        // Do it first: a capabilities failure must never collapse the picker back
        // to its single bundled preview model.
        let discoveredModels = try await client.models()
        if !discoveredModels.isEmpty {
            capabilities.models = discoveredModels
        }
        if let snapshot = try? await client.capabilities() {
            var merged = snapshot
            merged.models = capabilities.models
            capabilities = merged
        }
        if let active = capabilities.models.first(where: { $0.isActive == true }) ?? capabilities.models.first {
            activeModelID = active.id
            activeProviderID = active.provider
        }
    }

    func selectModel(_ model: HermesModel) async {
        do {
            try await client.selectModel(provider: model.provider, model: model.id)
            activeModelID = model.id
            activeProviderID = model.provider
            capabilities.models = capabilities.models.map { existing in
                var copy = existing
                copy.isActive = existing.id == model.id && existing.provider == model.provider
                return copy
            }
        } catch {
            messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
        }
    }

    func refreshReasoningEffort() async {
        if let effort = try? await client.reasoningEffort() {
            reasoningEffort = effort
        }
    }

    func setReasoningEffort(_ effort: String) async {
        let previous = reasoningEffort
        reasoningEffort = HermesReasoningEffort(effort: effort, options: reasoningEffort.options)
        do {
            try await client.setReasoningEffort(effort)
        } catch {
            reasoningEffort = previous
            messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
        }
    }

    func select(session: HermesSession) async {
        resetLiveDraftTracking(removeMessage: true)
        selectedSessionID = session.id
        do {
            let fresh = try await client.messages(sessionID: session.id)
            guard selectedSessionID == session.id else { return }
            messages = fresh
        } catch {
            guard selectedSessionID == session.id else { return }
            messages = [HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: [])]
        }
    }

    // MARK: - External-session live draft

    /// Starts mirroring a turn initiated by Desktop/CLI/Telegram while this
    /// chat is on screen. Repeated starts replace the prior task, which keeps
    /// SwiftUI appearance changes and compact/wide layout switches safe.
    func startLiveDraftPolling() {
        stopLiveDraftPolling()
        liveDraftPollGeneration &+= 1
        let generation = liveDraftPollGeneration
        liveDraftTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.pollLiveDrafts(generation: generation)
        }
    }

    func stopLiveDraftPolling() {
        liveDraftPollGeneration &+= 1
        liveDraftTask?.cancel()
        liveDraftTask = nil
        resetLiveDraftTracking(removeMessage: true)
    }

    private func pollLiveDrafts(generation: Int) async {
        while !Task.isCancelled, generation == liveDraftPollGeneration {
            var delay: Duration = .seconds(1)

            if isAppActive, case .connected = connection, let sessionID = selectedSessionID {
                prepareLiveDraftTracking(for: sessionID)

                // The existing mobile SSE stream owns `messages` for its
                // entire turn. Never poll or merge over it.
                if isStreaming {
                    delay = .milliseconds(250)
                } else {
                    do {
                        let draft = try await client.liveDraft(sessionID: sessionID)
                        guard !Task.isCancelled,
                              generation == liveDraftPollGeneration,
                              selectedSessionID == sessionID else { continue }
                        await consumeLiveDraft(draft, sessionID: sessionID, generation: generation)
                        delay = draft.active && !draft.done ? .milliseconds(150) : .seconds(1)
                    } catch is CancellationError {
                        return
                    } catch {
                        // Live state is best effort (and older dashboards do
                        // not expose it). Keep the chat usable and retry at the
                        // inactive cadence instead of publishing an error row.
                        delay = .seconds(1)
                    }
                }
            }

            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    private func prepareLiveDraftTracking(for sessionID: String) {
        guard liveDraftSessionID != sessionID else { return }
        resetLiveDraftTracking(removeMessage: true)
        liveDraftSessionID = sessionID
    }

    /// Applies one full-text live snapshot. Kept internal so focused tests can
    /// exercise merge/dedup/session-race behavior without timing a poll loop.
    func consumeLiveDraft(_ draft: HermesLiveDraft, sessionID: String, generation: Int? = nil) async {
        guard selectedSessionID == sessionID else { return }
        if let generation, generation != liveDraftPollGeneration { return }
        prepareLiveDraftTracking(for: sessionID)

        // A fresh active turn may restart its sequence after the previous
        // terminal snapshot. Treat activity as authoritative in that case.
        if draft.active, !draft.done,
           let completed = liveDraftCompletedSequence,
           draft.sequence <= completed {
            liveDraftCompletedSequence = nil
            liveDraftSequence = -1
        }

        liveDraftIsActive = draft.active && !draft.done
        let hasDraftText = !draft.text.isEmpty && (draft.active || draft.done)
        if hasDraftText,
           draft.sequence >= liveDraftSequence,
           liveDraftCompletedSequence != draft.sequence {
            let messageID = liveDraftMessageID ?? "external-live-draft-\(sessionID)"
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].text = draft.text
            } else {
                messages.append(HermesMessage(
                    id: messageID,
                    role: .assistant,
                    text: draft.text,
                    createdAt: .now,
                    toolCalls: []
                ))
            }
            liveDraftMessageID = messageID
            liveDraftSequence = draft.sequence
        }

        // `done` is the normal terminal signal. If a terminal poll was missed
        // and the route already returns inactive/404, a local draft is also a
        // reason to reconcile with the canonical persisted transcript.
        let shouldRefreshPersisted = draft.done || (!draft.active && liveDraftMessageID != nil)
        guard shouldRefreshPersisted,
              liveDraftCompletedSequence != draft.sequence,
              let fresh = try? await client.messages(sessionID: sessionID),
              selectedSessionID == sessionID else { return }
        if let generation, generation != liveDraftPollGeneration { return }

        messages = fresh
        liveDraftMessageID = nil
        liveDraftIsActive = false
        liveDraftSequence = draft.sequence
        if draft.done {
            liveDraftCompletedSequence = draft.sequence
        }
    }

    private func resetLiveDraftTracking(removeMessage: Bool) {
        if removeMessage, let liveDraftMessageID {
            messages.removeAll { $0.id == liveDraftMessageID }
        }
        liveDraftSessionID = nil
        liveDraftMessageID = nil
        liveDraftSequence = -1
        liveDraftCompletedSequence = nil
        liveDraftIsActive = false
    }

    /// Keep pull-to-refresh visible long enough to communicate that the
    /// desktop state was checked, even when both local requests return almost
    /// instantly. The refresh itself and the minimum display delay run in
    /// parallel, so slow networks are never delayed further.
    func refreshSessionListForPull() async {
        let minimumDisplay = Task {
            try? await Task.sleep(for: .milliseconds(700))
        }
        try? await refreshSessions()
        try? await refreshCapabilities()
        _ = await minimumDisplay.value
    }

    func sendComposer() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        composerText = ""
        let userMessage = HermesMessage(id: UUID().uuidString, role: .user, text: text, createdAt: .now, toolCalls: [])
        messages.append(userMessage)
        isStreaming = true

        do {
            var attachments = pendingAttachments
            pendingAttachments = []
            for index in attachments.indices {
                if attachments[index].path == nil {
                    if let uploaded = try? await client.uploadAttachment(fileURL: attachmentFileURL(for: attachments[index])) {
                        attachments[index].path = uploaded
                    }
                }
            }
            let stream = try await client.send(OutboundPrompt(sessionID: selectedSessionID, text: text, attachments: attachments)) { [weak self] request in
                Task { @MainActor in
                    self?.pendingApproval = request
                }
            }
            for try await update in stream {
                if let index = messages.lastIndex(where: { $0.id == update.id }) {
                    messages[index] = update
                } else {
                    messages.append(update)
                }
            }
            try? await refreshSessions()
            if let resolved = await client.lastTranscriptSessionID(), resolved != selectedSessionID {
                // The backend could not resume the requested conversation and
                // landed the turn in a fresh session instead. Follow it so the
                // reply stays visible in the right chat instead of vanishing.
                selectedSessionID = resolved
            }
            // Canonical transcript: the stream only carried live deltas with
            // local ids. Reload from the backend so the chat shows the real
            // rows (DB ids, final tool calls, no duplicates).
            if let sessionID = selectedSessionID,
               let fresh = try? await client.messages(sessionID: sessionID) {
                messages = fresh
            }
        } catch {
            messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
        }
        isStreaming = false
        // The turn completed while the app was visible: no background
        // "reply ready" alert needed anymore.
        NotificationManager.shared.clearPendingTurn()
    }

    /// Answer a pending dangerous-command approval. "once" / "session" /
    /// "always" unblock the turn; "deny" blocks it.
    func respond(toApproval request: ApprovalRequest, verdict: String) {
        pendingApproval = nil
        Task {
            do {
                try await client.approve(approvalID: request.id, verdict: verdict)
            } catch {
                messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
            }
        }
    }

    func addPendingAttachment(_ attachment: OutboundPrompt.Attachment) {
        pendingAttachments.append(attachment)
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func attachDesktopFile(path: String) async throws {
        let attached = try await client.attachDesktopFile(path: path)
        pendingAttachments.append(
            OutboundPrompt.Attachment(
                id: attached.id,
                filename: attached.name,
                mimeType: attached.mimeType,
                sizeBytes: attached.sizeBytes,
                path: attached.path
            )
        )
    }

    private func attachmentFileURL(for attachment: OutboundPrompt.Attachment) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(attachment.filename)
    }

    func stop() async {
        guard let selectedSessionID else { return }
        do { try await client.stop(sessionID: selectedSessionID) } catch {}
        isStreaming = false
        NotificationManager.shared.clearPendingTurn()
    }

    func disconnect(clearPairing: Bool = false) {
        stopLiveDraftPolling()
        stopAutoRefresh()
        connection = .disconnected
        selectedSessionID = nil
        sessions = []
        messages = []
        isStreaming = false
        deepLinkSessionID = nil
        writeWidgetSnapshot()
        if clearPairing {
            KeychainStore.deleteToken()
            UserDefaults.standard.removeObject(forKey: "hermes.host")
            UserDefaults.standard.removeObject(forKey: "hermes.profile")
        }
    }

    // MARK: - Desktop maintenance (hermes doctor / update)

    @Published var toolOutput = ""
    @Published var toolIssues: [HermesDoctorIssue] = []
    @Published var toolTitle = ""
    @Published var toolRunning = false
    @Published var updateStatus: HermesUpdateStatus?

    func runDesktopTool(_ kind: DesktopTool) async {
        guard case .connected = connection else {
            toolOutput = "Not connected to a desktop."
            return
        }
        toolTitle = kind.title
        toolRunning = true
        toolOutput = "Running \(kind.command)…"
        toolIssues = []
        do {
            switch kind {
            case .doctor:
                let report = try await client.runDoctor()
                toolOutput = report.output
                toolIssues = report.issues
            case .update:
                toolOutput = try await client.runUpdate()
                await refreshUpdateStatus()
            }
        } catch {
            toolOutput = "Failed: \(error.localizedDescription)"
        }
        toolRunning = false
    }

    func refreshUpdateStatus() async {
        guard case .connected = connection else { return }
        updateStatus = try? await client.fetchUpdateStatus()
    }

    @Published var stats: HermesStatsReport?
    @Published var statsError: String?

    func refreshStats() async {
        guard case .connected = connection else { return }
        do {
            stats = try await client.fetchStats()
            statsError = nil
        } catch {
            statsError = error.localizedDescription
        }
    }

    enum DesktopTool {
        case doctor, update
        var title: String { self == .doctor ? "Hermes doctor" : "Hermes update" }
        var command: String { self == .doctor ? "hermes doctor" : "hermes update --yes" }
    }

    /// Foreground poll loop: refreshes sessions/cron/memory/approvals every
    /// 30 s while the app is active and connected, so changes made on the
    /// desktop show up without reopening screens. Never touches `messages`
    /// while a chat streams (the stream owns those rows).
    private func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled, self.isAppActive, case .connected = self.connection else { continue }
                if !self.isStreaming && !self.liveDraftIsActive {
                    try? await self.refreshSessions()
                }
                await self.refreshCron()
                await self.refreshSkillsMemory()
                await self.checkPendingApprovals()
                self.writeWidgetSnapshot()
            }
        }
    }

    /// Publishes the current app state to the shared App Group container so
    /// the home-screen and lock-screen widgets can render it. Called on
    /// connect, on every foreground refresh tick and on disconnect.
    func writeWidgetSnapshot() {
        var snapshot = HermesWidgetSnapshot()
        if case .connected = connection {
            snapshot.gatewayUp = true
        }
        // The widget always shows the MOST RECENT session (first in the
        // desktop list, ordered by activity), not whatever the app happens
        // to have selected. Cron-generated output sessions are not real
        // conversations, so skip source "cron" and show the last genuine
        // chat; fall back to the raw first row if every session is cron.
        if let session = Self.widgetSession(from: sessions) {
            snapshot.sessionID = session.id
            snapshot.sessionTitle = session.title
            snapshot.sessionSubtitle = session.subtitle
        }
        if let last = messages.last, !last.text.isEmpty, selectedSessionID == snapshot.sessionID {
            snapshot.lastMessagePreview = String(last.text.prefix(80))
        }
        let nextJob = cronJobs
            .filter { $0.enabled && $0.state != "paused" }
            .compactMap { job -> (title: String, date: Date)? in
                guard let raw = job.nextRunAt, let date = Self.isoDate(raw) else { return nil }
                return (job.name, date)
            }
            .min { $0.date < $1.date }
        if let nextJob {
            snapshot.nextCronTitle = nextJob.title
            snapshot.nextCronDate = nextJob.date
        }
        snapshot.pendingApprovalCommand = pendingApproval?.command ?? ""
        snapshot.updatedAt = .now
        snapshot.write()
    }

    /// Pick the session the widget's SESSION block should show: the most
    /// recent row that is a real conversation, skipping cron-generated output
    /// sessions (source == "cron"). Falls back to the raw first row when every
    /// session is cron. `sessions` is expected in activity order (newest first).
    static func widgetSession(from sessions: [HermesSession]) -> HermesSession? {
        sessions.first(where: { $0.source?.lowercased() != "cron" }) ?? sessions.first
    }

    private static func isoDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: raw) ?? standard.date(from: raw)
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // -- remote tunnel -------------------------------------------------

    func refreshTunnelStatus() async {
        guard case .connected = connection else { return }
        do {
            tunnelStatus = try await client.tunnelStatus()
        } catch {
            // Tunnel routes only exist on a current plugin/bridge — ignore
            // when the backend predates them.
        }
    }

    func startTunnel() async {
        do {
            tunnelStatus = try await client.tunnelStart()
        } catch {
            tunnelStatus = HermesTunnelStatus(ok: false, active: false, provider: "", publicUrl: "", localUrl: "", error: error.localizedDescription)
        }
    }

    func stopTunnel() async {
        do {
            try await client.tunnelStop()
            tunnelStatus = HermesTunnelStatus(ok: true, active: false, provider: "", publicUrl: "", localUrl: "", error: "")
        } catch {
            tunnelStatus = HermesTunnelStatus(ok: false, active: false, provider: "", publicUrl: "", localUrl: "", error: error.localizedDescription)
        }
    }

    // -- cron jobs --------------------------------------------------------

    func refreshCron() async {
        guard case .connected = connection else { return }
        do {
            cronJobs = try await client.cronJobs()
            cronUnavailable = false
        } catch {
            // Only the plugin backend ships cron routes (the standalone
            // bridge does not) — degrade to an empty, flagged list.
            cronJobs = []
            cronUnavailable = true
        }
    }

    func cronPause(jobID: String) async {
        do {
            let updated = try await client.cronPause(jobID: jobID)
            replaceCronJob(updated)
        } catch {}
    }

    func cronResume(jobID: String) async {
        do {
            let updated = try await client.cronResume(jobID: jobID)
            replaceCronJob(updated)
        } catch {}
    }

    func cronRun(jobID: String) async {
        do {
            let updated = try await client.cronRun(jobID: jobID)
            replaceCronJob(updated)
        } catch {}
    }

    func cronRemove(jobID: String) async {
        do {
            try await client.cronRemove(jobID: jobID)
            cronJobs.removeAll { $0.id == jobID }
        } catch {}
    }

    /// Create a job from the phone and refresh the list (throws so the
    /// creator sheet can surface validation errors from the gateway).
    func cronCreate(name: String?, prompt: String, schedule: String, skills: [String]?, deliver: String?, enabled: Bool) async throws {
        let created = try await client.cronCreate(name: name, prompt: prompt, schedule: schedule, skills: skills, deliver: deliver, enabled: enabled)
        if let idx = cronJobs.firstIndex(where: { $0.id == created.id }) {
            cronJobs[idx] = created
        } else {
            cronJobs.append(created)
        }
    }

    /// Thin passthrough so CronJobsView can load a job's execution history.
    func cronExecutions(jobID: String) async throws -> [HermesCronExecution] {
        try await client.cronExecutions(jobID: jobID)
    }

    // -- skills & memory ----------------------------------------------------

    func refreshSkillsMemory() async {
        guard case .connected = connection else { return }
        do {
            async let skillsPromise = client.skills()
            async let memoryPromise = client.memory()
            let (skillsResult, memoryResult) = try await (skillsPromise, memoryPromise)
            skills = skillsResult
            memory = memoryResult
        } catch {}
    }

    func skillDetail(name: String) async -> HermesSkill? {
        try? await client.skill(name: name)
    }

    @discardableResult
    func memoryAppend(target: String, content: String) async -> Bool {
        guard let entries = try? await client.memoryAppend(target: target, content: content) else { return false }
        switch target {
        case "user":
            memory.user = entries
        default:
            memory.memory = entries
        }
        return true
    }

    @discardableResult
    func memoryUpdate(target: String, index: Int, content: String) async -> Bool {
        guard let entries = try? await client.memoryUpdate(target: target, index: index, content: content) else { return false }
        switch target {
        case "user":
            memory.user = entries
        default:
            memory.memory = entries
        }
        return true
    }

    @discardableResult
    func memoryDelete(target: String, index: Int) async -> Bool {
        guard let entries = try? await client.memoryDelete(target: target, index: index) else { return false }
        switch target {
        case "user":
            memory.user = entries
        default:
            memory.memory = entries
        }
        return true
    }

    private func replaceCronJob(_ job: HermesCronJob) {
        if let index = cronJobs.firstIndex(where: { $0.id == job.id }) {
            cronJobs[index] = job
        } else {
            cronJobs.append(job)
        }
    }

    func files(path: String? = nil) async throws -> HermesFileListing {
        try await client.files(path: path)
    }

    func readFile(path: String) async throws -> HermesFileContent {
        try await client.readFile(path: path)
    }

    func renameSession(id: String, title: String) async throws {
        try await client.renameSession(id: id, title: title)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].title = title
        }
        try? await refreshSessions()
    }

    func pinSession(id: String, pinned: Bool) async throws {
        try await client.pinSession(id: id, pinned: pinned)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].pinned = pinned
        }
        try? await refreshSessions()
    }

    func archiveSession(id: String) async throws {
        try await client.archiveSession(id: id)
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = nil
            messages = []
        }
        try? await refreshSessions()
        writeWidgetSnapshot()
    }

    func deleteSession(id: String) async throws {
        try await client.deleteSession(id: id)
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = nil
            messages = []
        }
        try? await refreshSessions()
        writeWidgetSnapshot()
    }

    /// Loads the archived chats (hidden from the main list) for the
    /// archived-sessions sheet.
    func loadArchivedSessions() async {
        archivedSessions = (try? await client.archivedSessions()) ?? []
    }

    /// Writes the current conversation to a temporary markdown file and
    /// returns its URL, ready for a ShareLink export.
    func exportMarkdownFileURL() -> URL? {
        guard let session = selectedSession else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var md = "# \(session.title)\n\n"
        md += "*\(formatter.string(from: session.updatedAt))"
        if let source = session.source, !source.isEmpty { md += " · \(source)" }
        md += "*\n\n---\n\n"
        for message in messages where message.isTranscriptVisible {
            switch message.role {
            case .user:
                md += "## User\n\n\(message.text)\n\n"
            case .assistant:
                md += "## Hermes\n\n\(message.text)\n\n"
            default:
                break
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-\(session.id).md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Un-archives a chat and moves it back to the main list.
    func restoreSession(id: String) async throws {
        try await client.archiveSession(id: id, archived: false)
        archivedSessions.removeAll { $0.id == id }
        try? await refreshSessions()
    }

    func runCommand(_ command: MobileCommand) async {
        switch command {
        case .newChat:
            do {
                let sessionID = try await client.newChat()
                selectedSessionID = sessionID
                messages = []
                try? await refreshSessions()
                writeWidgetSnapshot()
            } catch {
                messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
            }
        case .stop:
            await stop()
        case .continueLast:
            composerText = "Continue"
            await sendComposer()
        case .togglePrivacy:
            privacyMode.toggle()
        case .refresh:
            try? await refreshSessions()
            try? await refreshCapabilities()
        }
    }

    /// Handles widget deep links: `hermes://session/<id>` selects a chat,
    /// `hermes://new-chat` starts one. The session id is mirrored into
    /// `deepLinkSessionID` so the shell knows to bring up the chat pane.
    func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "hermes" else { return }
        let path = components.path
        if path == "/new-chat" {
            Task { await runCommand(.newChat) }
            deepLinkSessionID = "new-chat"
        } else if path.hasPrefix("/session/") {
            let id = String(path.dropFirst("/session/".count))
            guard !id.isEmpty else { return }
            if let session = sessions.first(where: { $0.id == id }) {
                Task { await select(session: session) }
            }
            deepLinkSessionID = id
        }
    }
}

enum MobileCommand: String, CaseIterable, Identifiable {
    case newChat
    case stop
    case continueLast
    case togglePrivacy
    case refresh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newChat: "New chat"
        case .stop: "Stop running turn"
        case .continueLast: "Continue last task"
        case .togglePrivacy: "Toggle privacy mode"
        case .refresh: "Refresh desktop state"
        }
    }

    var icon: String {
        switch self {
        case .newChat: "plus.message"
        case .stop: "stop.fill"
        case .continueLast: "arrow.clockwise"
        case .togglePrivacy: "eye.slash"
        case .refresh: "arrow.triangle.2.circlepath"
        }
    }
}

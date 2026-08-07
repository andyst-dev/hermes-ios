import Foundation

final class MockHermesTransport: HermesTransport, @unchecked Sendable {
    private var sessionList: [HermesSession] = PreviewData.sessions

    func connect(to host: HermesHost) async throws -> HermesHost {
        try await Task.sleep(for: .milliseconds(350))
        return host
    }

    func fetchSessions() async throws -> [HermesSession] {
        sessionList
    }

    func fetchMessages(sessionID: String) async throws -> [HermesMessage] {
        PreviewData.messages
    }

    func fetchCapabilities() async throws -> HermesCapabilitySnapshot {
        PreviewData.capabilities
    }

    func fetchModels() async throws -> [HermesModel] {
        PreviewData.capabilities.models
    }

    func selectModel(provider: String, model: String) async throws {}

    func fetchReasoningEffort() async throws -> HermesReasoningEffort {
        HermesReasoningEffort(effort: "medium", options: HermesReasoningEffort.defaultOptions)
    }

    func setReasoningEffort(_ effort: String) async throws {}

    func newChat() async throws -> String {
        "mock-session-\(UUID().uuidString.prefix(8))"
    }

    func fetchFiles(path: String?) async throws -> HermesFileListing {
        HermesFileListing(
            path: path ?? "",
            entries: [
                HermesFileEntry(name: "reference.png", path: "reference.png", isDirectory: false, size: 512, mtime: nil, mimeType: "image/png"),
                HermesFileEntry(name: "README.md", path: "README.md", isDirectory: false, size: 512, mtime: nil, mimeType: "text/markdown"),
                HermesFileEntry(name: "projects", path: "projects", isDirectory: true, size: nil, mtime: nil, mimeType: nil),
            ]
        )
    }

    func readFile(path: String) async throws -> HermesFileContent {
        HermesFileContent(name: path, content: "# Mock file\n\nThis is demo content.", truncated: false)
    }

    func renameSession(id: String, title: String) async throws {
        if let index = sessionList.firstIndex(where: { $0.id == id }) {
            sessionList[index].title = title
        }
    }

    func pinSession(id: String, pinned: Bool) async throws {
        if let index = sessionList.firstIndex(where: { $0.id == id }) {
            sessionList[index].pinned = pinned
        }
    }

    func archiveSession(id: String) async throws {
        sessionList.removeAll { $0.id == id }
    }

    func uploadAttachment(fileURL: URL) async throws -> String {
        "/mock/\(fileURL.lastPathComponent)"
    }

    func attachDesktopFile(path: String) async throws -> HermesDesktopAttachment {
        HermesDesktopAttachment(id: UUID(), name: URL(fileURLWithPath: path).lastPathComponent, path: "/mock/\(path)", mimeType: "image/png", sizeBytes: 512)
    }

    func send(_ prompt: OutboundPrompt, onApproval: @escaping @Sendable (ApprovalRequest) -> Void) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chunks = [
                    "Je lance ça proprement.",
                    "\n\nJe vais vérifier le contexte, patcher minimalement, puis lancer les tests.",
                    "\n\nEnsuite je prépare un PR body clean sans chemins locaux ni secrets."
                ]
                var current = HermesMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    text: "",
                    createdAt: .now,
                    toolCalls: [
                        HermesToolCall(id: UUID().uuidString, name: "terminal", command: "git diff --check", status: .running, summary: "Validating patch hygiene")
                    ]
                )
                for chunk in chunks {
                    try await Task.sleep(for: .milliseconds(260))
                    current.text += chunk
                    continuation.yield(current)
                }
                current.toolCalls[0].status = .succeeded
                current.toolCalls[0].summary = "No whitespace errors"
                continuation.yield(current)
                continuation.finish()
            }
        }
    }

    func approve(approvalID: String, verdict: String) async throws {}

    func lastTranscriptSessionID() async -> String? {
        nil
    }

    func stop(sessionID: String) async throws {}

    func tunnelStatus() async throws -> HermesTunnelStatus {
        HermesTunnelStatus(ok: true, active: false, provider: "", publicUrl: "", localUrl: "http://127.0.0.1:8765", error: "")
    }

    func tunnelStart() async throws -> HermesTunnelStatus {
        HermesTunnelStatus(
            ok: true,
            active: true,
            provider: "cloudflared",
            publicUrl: "https://demo-mock.trycloudflare.com",
            localUrl: "http://127.0.0.1:8765",
            error: ""
        )
    }

    func tunnelStop() async throws {}

    func fetchCronJobs() async throws -> [HermesCronJob] {
        [
            HermesCronJob(
                id: "daily-briefing",
                name: "Daily briefing",
                prompt: "Summarize the top headlines and my unread sessions",
                schedule: "0 9 * * *",
                scheduleDisplay: "every day at 09:00",
                state: "scheduled",
                enabled: true,
                nextRunAt: "2026-08-09T09:00:00+02:00",
                lastRunAt: "2026-08-08T09:00:00+02:00",
                deliver: "telegram:Home",
                skills: [],
                latestExecution: HermesCronExecution(id: "ex9", status: "completed", startedAt: "2026-08-08T09:00:00+02:00", finishedAt: "2026-08-08T09:00:42+02:00", summary: "Delivered to telegram:Home")
            ),
            HermesCronJob(
                id: "nightly-backup",
                name: "Nightly repo backup",
                prompt: "Commit and push all local repo changes",
                schedule: "0 2 * * *",
                scheduleDisplay: "every day at 02:00",
                state: "paused",
                enabled: false,
                nextRunAt: nil,
                lastRunAt: "2026-08-06T02:00:00+02:00",
                deliver: "local",
                skills: ["github-delivery-hygiene"],
                latestExecution: nil
            ),
        ]
    }

    func fetchCronExecutions(jobID: String) async throws -> [HermesCronExecution] {
        [
            HermesCronExecution(id: "ex9", status: "completed", startedAt: "2026-08-08T09:00:00+02:00", finishedAt: "2026-08-08T09:00:42+02:00", summary: "Delivered to telegram:Home"),
            HermesCronExecution(id: "ex8", status: "completed", startedAt: "2026-08-07T09:00:00+02:00", finishedAt: "2026-08-07T09:00:55+02:00", summary: "Delivered to telegram:Home"),
        ]
    }

    func cronPause(jobID: String) async throws -> HermesCronJob {
        HermesCronJob(id: jobID, name: "Paused job", prompt: "", schedule: "", scheduleDisplay: "paused", state: "paused", enabled: false, nextRunAt: nil, lastRunAt: nil, deliver: "", skills: [], latestExecution: nil)
    }

    func cronResume(jobID: String) async throws -> HermesCronJob {
        HermesCronJob(id: jobID, name: "Resumed job", prompt: "", schedule: "", scheduleDisplay: "scheduled", state: "scheduled", enabled: true, nextRunAt: nil, lastRunAt: nil, deliver: "", skills: [], latestExecution: nil)
    }

    func cronRun(jobID: String) async throws -> HermesCronJob {
        HermesCronJob(id: jobID, name: "Triggered job", prompt: "", schedule: "", scheduleDisplay: "running", state: "running", enabled: true, nextRunAt: nil, lastRunAt: nil, deliver: "", skills: [], latestExecution: nil)
    }

    func cronRemove(jobID: String) async throws {}

    func fetchPendingNotifications() async throws -> HermesPendingNotifications {
        HermesPendingNotifications(
            ok: true,
            approvals: [HermesPendingApproval(id: "appr-demo", sessionID: "sess-demo", command: "brew upgrade --all")],
            recentCron: [
                HermesRecentCronRun(jobID: "daily-briefing", status: "completed", claimedAt: "2026-08-08T08:00:00+02:00", finishedAt: "2026-08-08T08:00:30+02:00", summary: "Delivered to telegram:Home")
            ]
        )
    }
}

import Foundation

protocol HermesTransport: Sendable {
    func connect(to host: HermesHost) async throws -> HermesHost
    func fetchSessions() async throws -> [HermesSession]
    func fetchArchivedSessions() async throws -> [HermesSession]
    func fetchMessages(sessionID: String) async throws -> [HermesMessage]
    func fetchCapabilities() async throws -> HermesCapabilitySnapshot
    func fetchModels() async throws -> [HermesModel]
    func selectModel(provider: String, model: String) async throws
    func fetchReasoningEffort() async throws -> HermesReasoningEffort
    func setReasoningEffort(_ effort: String) async throws
    func send(_ prompt: OutboundPrompt, onApproval: @escaping @Sendable (ApprovalRequest) -> Void) async throws -> AsyncThrowingStream<HermesMessage, Error>
    /// The session id the last chat turn actually landed in. Differs from the
    /// requested id when the backend had to create a fresh session (e.g. the
    /// conversation was never ACP-persisted, like one created on Desktop).
    func lastTranscriptSessionID() async -> String?
    func approve(approvalID: String, verdict: String) async throws
    func newChat() async throws -> String
    func stop(sessionID: String) async throws
    func fetchFiles(path: String?) async throws -> HermesFileListing
    func readFile(path: String) async throws -> HermesFileContent
    func renameSession(id: String, title: String) async throws
    func pinSession(id: String, pinned: Bool) async throws
    func archiveSession(id: String, archived: Bool) async throws
    /// Permanently deletes a session on the desktop (hard delete).
    func deleteSession(id: String) async throws
    /// Desktop maintenance — runs `hermes doctor` / `hermes update --yes`
    /// on the desktop and returns the parsed report / CLI output.
    func runDoctor() async throws -> HermesDoctorReport
    func runUpdate() async throws -> String
    func fetchUpdateStatus() async throws -> HermesUpdateStatus
    func uploadAttachment(fileURL: URL) async throws -> String
    func attachDesktopFile(path: String) async throws -> HermesDesktopAttachment
    /// Remote access tunnel (cloudflared quick tunnel / ngrok) — lets the
    /// iPhone reach the desktop from outside the LAN, no VPN.
    func tunnelStatus() async throws -> HermesTunnelStatus
    func tunnelStart() async throws -> HermesTunnelStatus
    func tunnelStop() async throws
    /// Gateway scheduled jobs: list, control (pause/resume/run/remove) and
    /// per-job execution history.
    func fetchCronJobs() async throws -> [HermesCronJob]
    func fetchCronExecutions(jobID: String) async throws -> [HermesCronExecution]
    func cronPause(jobID: String) async throws -> HermesCronJob
    func cronResume(jobID: String) async throws -> HermesCronJob
    func cronRun(jobID: String) async throws -> HermesCronJob
    func cronRemove(jobID: String) async throws
    /// Create a cron job from the phone (name/prompt/schedule/skills/deliver).
    func cronCreate(name: String?, prompt: String, schedule: String, skills: [String]?, deliver: String?, enabled: Bool) async throws -> HermesCronJob
    /// Background-alert poll: approvals waiting for a phone verdict + cron
    /// runs that just finished (drives local notifications, no APNs).
    func fetchPendingNotifications() async throws -> HermesPendingNotifications
    /// Skills catalog and persistent memory (read) + memory append.
    func fetchSkills() async throws -> [HermesSkill]
    func fetchSkill(name: String) async throws -> HermesSkill
    func fetchMemory() async throws -> HermesMemory
    func appendMemory(target: String, content: String) async throws -> [HermesMemoryEntry]
    /// Edit or delete one memory entry (agent notes or user profile).
    func updateMemory(target: String, index: Int, content: String) async throws -> [HermesMemoryEntry]
    func deleteMemory(target: String, index: Int) async throws -> [HermesMemoryEntry]
}

enum HermesTransportError: Error, LocalizedError {
    case notConnected
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to a Hermes host."
        case .invalidResponse: "The Hermes host returned an invalid response."
        case .server(let message): message
        }
    }
}

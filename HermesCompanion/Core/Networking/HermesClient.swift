import Foundation

@MainActor
final class HermesClient: ObservableObject {
    private let transport: any HermesTransport

    init(transport: any HermesTransport) {
        self.transport = transport
    }

    func connect(host: HermesHost) async throws -> HermesHost {
        try await transport.connect(to: host)
    }

    func sessions() async throws -> [HermesSession] {
        try await transport.fetchSessions()
    }

    func archivedSessions() async throws -> [HermesSession] {
        try await transport.fetchArchivedSessions()
    }

    func messages(sessionID: String) async throws -> [HermesMessage] {
        try await transport.fetchMessages(sessionID: sessionID)
    }

    func capabilities() async throws -> HermesCapabilitySnapshot {
        try await transport.fetchCapabilities()
    }

    func models() async throws -> [HermesModel] {
        try await transport.fetchModels()
    }

    func selectModel(provider: String, model: String) async throws {
        try await transport.selectModel(provider: provider, model: model)
    }

    func reasoningEffort() async throws -> HermesReasoningEffort {
        try await transport.fetchReasoningEffort()
    }

    func setReasoningEffort(_ effort: String) async throws {
        try await transport.setReasoningEffort(effort)
    }

    func send(_ prompt: OutboundPrompt, onApproval: @escaping @Sendable (ApprovalRequest) -> Void) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        try await transport.send(prompt, onApproval: onApproval)
    }

    func lastTranscriptSessionID() async -> String? {
        await transport.lastTranscriptSessionID()
    }

    func approve(approvalID: String, verdict: String) async throws {
        try await transport.approve(approvalID: approvalID, verdict: verdict)
    }

    func newChat() async throws -> String {
        try await transport.newChat()
    }

    func stop(sessionID: String) async throws {
        try await transport.stop(sessionID: sessionID)
    }

    func files(path: String?) async throws -> HermesFileListing {
        try await transport.fetchFiles(path: path)
    }

    func readFile(path: String) async throws -> HermesFileContent {
        try await transport.readFile(path: path)
    }

    func renameSession(id: String, title: String) async throws {
        try await transport.renameSession(id: id, title: title)
    }

    func pinSession(id: String, pinned: Bool) async throws {
        try await transport.pinSession(id: id, pinned: pinned)
    }

    func archiveSession(id: String, archived: Bool = true) async throws {
        try await transport.archiveSession(id: id, archived: archived)
    }

    func deleteSession(id: String) async throws {
        try await transport.deleteSession(id: id)
    }

    func runDoctor() async throws -> HermesDoctorReport {
        try await transport.runDoctor()
    }

    func runUpdate() async throws -> String {
        try await transport.runUpdate()
    }

    func fetchUpdateStatus() async throws -> HermesUpdateStatus {
        try await transport.fetchUpdateStatus()
    }

    func fetchStats() async throws -> HermesStatsReport {
        try await transport.fetchStats()
    }

    func uploadAttachment(fileURL: URL) async throws -> String {
        try await transport.uploadAttachment(fileURL: fileURL)
    }

    func attachDesktopFile(path: String) async throws -> HermesDesktopAttachment {
        try await transport.attachDesktopFile(path: path)
    }

    func tunnelStatus() async throws -> HermesTunnelStatus {
        try await transport.tunnelStatus()
    }

    func tunnelStart() async throws -> HermesTunnelStatus {
        try await transport.tunnelStart()
    }

    func tunnelStop() async throws {
        try await transport.tunnelStop()
    }

    func cronJobs() async throws -> [HermesCronJob] {
        try await transport.fetchCronJobs()
    }

    func cronExecutions(jobID: String) async throws -> [HermesCronExecution] {
        try await transport.fetchCronExecutions(jobID: jobID)
    }

    func cronPause(jobID: String) async throws -> HermesCronJob {
        try await transport.cronPause(jobID: jobID)
    }

    func cronResume(jobID: String) async throws -> HermesCronJob {
        try await transport.cronResume(jobID: jobID)
    }

    func cronRun(jobID: String) async throws -> HermesCronJob {
        try await transport.cronRun(jobID: jobID)
    }

    func cronRemove(jobID: String) async throws {
        try await transport.cronRemove(jobID: jobID)
    }

    func cronCreate(name: String?, prompt: String, schedule: String, skills: [String]?, deliver: String?, enabled: Bool) async throws -> HermesCronJob {
        try await transport.cronCreate(name: name, prompt: prompt, schedule: schedule, skills: skills, deliver: deliver, enabled: enabled)
    }

    func pendingNotifications() async throws -> HermesPendingNotifications {
        try await transport.fetchPendingNotifications()
    }

    func skills() async throws -> [HermesSkill] {
        try await transport.fetchSkills()
    }

    func skill(name: String) async throws -> HermesSkill {
        try await transport.fetchSkill(name: name)
    }

    func memory() async throws -> HermesMemory {
        try await transport.fetchMemory()
    }

    func memoryAppend(target: String, content: String) async throws -> [HermesMemoryEntry] {
        try await transport.appendMemory(target: target, content: content)
    }

    func memoryUpdate(target: String, index: Int, content: String) async throws -> [HermesMemoryEntry] {
        try await transport.updateMemory(target: target, index: index, content: content)
    }

    func memoryDelete(target: String, index: Int) async throws -> [HermesMemoryEntry] {
        try await transport.deleteMemory(target: target, index: index)
    }
}

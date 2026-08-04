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

    func send(_ prompt: OutboundPrompt) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        try await transport.send(prompt)
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

    func archiveSession(id: String) async throws {
        try await transport.archiveSession(id: id)
    }

    func uploadAttachment(fileURL: URL) async throws -> String {
        try await transport.uploadAttachment(fileURL: fileURL)
    }

    func attachDesktopFile(path: String) async throws -> HermesDesktopAttachment {
        try await transport.attachDesktopFile(path: path)
    }
}

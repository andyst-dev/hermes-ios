import Foundation

protocol HermesTransport: Sendable {
    func connect(to host: HermesHost) async throws -> HermesHost
    func fetchSessions() async throws -> [HermesSession]
    func fetchMessages(sessionID: String) async throws -> [HermesMessage]
    func fetchCapabilities() async throws -> HermesCapabilitySnapshot
    func fetchModels() async throws -> [HermesModel]
    func selectModel(provider: String, model: String) async throws
    func send(_ prompt: OutboundPrompt) async throws -> AsyncThrowingStream<HermesMessage, Error>
    func newChat() async throws -> String
    func stop(sessionID: String) async throws
    func fetchFiles(path: String?) async throws -> HermesFileListing
    func readFile(path: String) async throws -> HermesFileContent
    func renameSession(id: String, title: String) async throws
    func pinSession(id: String, pinned: Bool) async throws
    func archiveSession(id: String) async throws
    func uploadAttachment(fileURL: URL) async throws -> String
    func attachDesktopFile(path: String) async throws -> HermesDesktopAttachment
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

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

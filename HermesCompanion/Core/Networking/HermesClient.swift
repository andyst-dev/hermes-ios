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
}

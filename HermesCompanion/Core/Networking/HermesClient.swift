import Foundation

@MainActor
final class HermesClient: ObservableObject {
    private let transport: HermesTransport

    init(transport: HermesTransport) {
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

    func send(_ prompt: OutboundPrompt) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        try await transport.send(prompt)
    }

    func stop(sessionID: String) async throws {
        try await transport.stop(sessionID: sessionID)
    }
}

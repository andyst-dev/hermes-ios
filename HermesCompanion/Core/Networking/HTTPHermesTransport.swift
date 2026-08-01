import Foundation

/// Production-ready skeleton for the eventual Hermes desktop/dashboard API.
/// Kept separate from MockHermesTransport so the UI can ship before the pairing API lands.
struct HTTPHermesTransport: HermesTransport {
    var tokenProvider: @Sendable () -> String?
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String?) {
        self.urlSession = urlSession
        self.tokenProvider = tokenProvider
    }

    func connect(to host: HermesHost) async throws -> HermesHost {
        var request = URLRequest(url: host.baseURL.appending(path: "api/mobile/health"))
        request.timeoutInterval = 8
        addAuth(to: &request)
        let (_, response) = try await urlSession.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw HermesTransportError.invalidResponse
        }
        return host
    }

    func fetchSessions() async throws -> [HermesSession] {
        throw HermesTransportError.server("Mobile sessions API is not wired yet.")
    }

    func fetchMessages(sessionID: String) async throws -> [HermesMessage] {
        throw HermesTransportError.server("Mobile message API is not wired yet.")
    }

    func fetchCapabilities() async throws -> HermesCapabilitySnapshot {
        throw HermesTransportError.server("Mobile capabilities API is not wired yet.")
    }

    func send(_ prompt: OutboundPrompt) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        throw HermesTransportError.server("Mobile streaming API is not wired yet.")
    }

    func stop(sessionID: String) async throws {
        throw HermesTransportError.server("Mobile stop API is not wired yet.")
    }

    private func addAuth(to request: inout URLRequest) {
        guard let token = tokenProvider(), !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}

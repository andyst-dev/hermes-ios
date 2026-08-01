import Foundation

/// Real mobile REST transport for the Hermes desktop/dashboard backend.
/// Streaming and mutation endpoints stay explicit TODOs until the desktop bridge exposes them.
actor HTTPHermesTransport: HermesTransport {
    var tokenProvider: @Sendable () -> String?
    private let urlSession: URLSession
    private var baseURL: URL?
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String?) {
        self.urlSession = urlSession
        self.tokenProvider = tokenProvider
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func connect(to host: HermesHost) async throws -> HermesHost {
        baseURL = host.baseURL
        let _: MobileHealthResponse = try await get("api/mobile/health")
        return host
    }

    func fetchSessions() async throws -> [HermesSession] {
        let response: MobileSessionsResponse = try await get("api/mobile/sessions")
        return response.sessions
    }

    func fetchMessages(sessionID: String) async throws -> [HermesMessage] {
        let response: MobileMessagesResponse = try await get("api/mobile/sessions/\(sessionID)/messages")
        return response.messages
    }

    func fetchCapabilities() async throws -> HermesCapabilitySnapshot {
        try await get("api/mobile/capabilities")
    }

    func send(_ prompt: OutboundPrompt) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        throw HermesTransportError.server("Mobile streaming API is not wired yet.")
    }

    func stop(sessionID: String) async throws {
        throw HermesTransportError.server("Mobile stop API is not wired yet.")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let baseURL else { throw HermesTransportError.notConnected }
        var request = URLRequest(url: endpointURL(baseURL: baseURL, path: path))
        request.timeoutInterval = 12
        addAuth(to: &request)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesTransportError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw HermesTransportError.server(message)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HermesTransportError.server("Could not decode Hermes mobile response: \(error.localizedDescription)")
        }
    }

    private func addAuth(to request: inout URLRequest) {
        guard let token = tokenProvider(), !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
    }

    private func endpointURL(baseURL: URL, path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appending(path: String(component))
        }
    }
}

private struct MobileHealthResponse: Decodable {
    let ok: Bool
}

private struct MobileSessionsResponse: Decodable {
    let sessions: [HermesSession]
}

private struct MobileMessagesResponse: Decodable {
    let messages: [HermesMessage]
}

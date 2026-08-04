import Foundation

/// Real mobile REST transport for the Hermes desktop/dashboard backend.
actor HTTPHermesTransport: HermesTransport {
    var tokenProvider: @Sendable () -> String?
    private let urlSession: URLSession
    private var baseURL: URL?
    private var profile: String = "default"
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String?) {
        self.urlSession = urlSession
        self.tokenProvider = tokenProvider
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: raw) ?? standard.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(raw)")
        }
        self.decoder = decoder
    }

    func connect(to host: HermesHost) async throws -> HermesHost {
        baseURL = host.baseURL
        profile = host.profile
        let _: MobileHealthResponse = try await get("api/mobile/health")
        return host
    }

    func fetchSessions() async throws -> [HermesSession] {
        let response: MobileSessionsResponse = try await get("api/mobile/sessions")
        return response.sessions
    }

    func fetchMessages(sessionID: String) async throws -> [HermesMessage] {
        let response: MobileMessagesResponse = try await get("api/mobile/sessions/\(sessionID)/messages")
        return response.messages.filter(\.isTranscriptVisible)
    }

    func fetchCapabilities() async throws -> HermesCapabilitySnapshot {
        try await get("api/mobile/capabilities")
    }

    func fetchModels() async throws -> [HermesModel] {
        let response: MobileModelsResponse = try await get("api/mobile/models")
        return response.models
    }

    func selectModel(provider: String, model: String) async throws {
        let _: MobileModelSetResponse = try await post("api/mobile/model", body: HermesModelSelection(provider: provider, model: model))
    }

    func send(_ prompt: OutboundPrompt) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        let response: MobileChatResponse = try await post("api/mobile/chat", body: prompt, timeout: 600)
        return AsyncThrowingStream { continuation in
            for message in response.messages.filter(\.isTranscriptVisible) {
                continuation.yield(message)
            }
            continuation.finish()
        }
    }

    func stop(sessionID: String) async throws {
        let _: MobileStopResponse = try await post("api/mobile/stop", body: MobileStopRequest(sessionID: sessionID))
    }

    func newChat() async throws -> String {
        let response: MobileNewChatResponse = try await post("api/mobile/new-chat", body: EmptyBody())
        return response.sessionID
    }

    func fetchFiles(path: String?) async throws -> HermesFileListing {
        var queryItems: [URLQueryItem] = []
        if let path, !path.isEmpty {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        return try await dataRequest(path: "api/mobile/files", method: "GET", body: Optional<Data>.none, queryItems: queryItems)
    }

    func readFile(path: String) async throws -> HermesFileContent {
        try await dataRequest(path: "api/mobile/files/read", method: "GET", body: Optional<Data>.none, queryItems: [URLQueryItem(name: "path", value: path)])
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await dataRequest(path: path, method: "GET", body: Optional<Data>.none)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, timeout: TimeInterval = 12) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await dataRequest(path: path, method: "POST", body: data, timeout: timeout)
    }

    private func dataRequest<T: Decodable>(path: String, method: String, body: Data?, timeout: TimeInterval = 12, queryItems: [URLQueryItem] = []) async throws -> T {
        guard let baseURL else { throw HermesTransportError.notConnected }
        var request = URLRequest(url: endpointURL(baseURL: baseURL, path: path, queryItems: queryItems))
        request.timeoutInterval = timeout
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
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

    private func endpointURL(baseURL: URL, path: String, queryItems extra: [URLQueryItem] = []) -> URL {
        let raw = path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appending(path: String(component))
        }
        guard var components = URLComponents(url: raw, resolvingAgainstBaseURL: false) else { return raw }
        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: extra)
        if !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "profile", value: profile))
        }
        components.queryItems = queryItems
        return components.url ?? raw
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

private struct MobileModelsResponse: Decodable {
    let models: [HermesModel]
}

private struct MobileModelSetResponse: Decodable {
    let ok: Bool
}

private struct MobileChatResponse: Decodable {
    let sessionID: String
    let messages: [HermesMessage]
}

private struct MobileStopRequest: Encodable {
    let sessionID: String
}

private struct MobileStopResponse: Decodable {
    let ok: Bool
}

private struct MobileNewChatResponse: Decodable {
    let ok: Bool
    let sessionID: String
}

private struct EmptyBody: Encodable {}

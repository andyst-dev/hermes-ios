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
        let response: MobileModelsResponse = try await get("api/mobile/models", timeout: 90)
        return response.models
    }

    func selectModel(provider: String, model: String) async throws {
        let _: MobileModelSetResponse = try await post("api/mobile/model", body: HermesModelSelection(provider: provider, model: model))
    }

    func fetchReasoningEffort() async throws -> HermesReasoningEffort {
        struct EffortResponse: Decodable {
            let effort: String
            let options: [String]
        }
        let response: EffortResponse = try await get("api/mobile/model/effort")
        return HermesReasoningEffort(
            effort: response.effort,
            options: response.options.isEmpty ? HermesReasoningEffort.defaultOptions : response.options
        )
    }

    func setReasoningEffort(_ effort: String) async throws {
        struct EffortBody: Encodable {
            let effort: String
        }
        struct EffortResponse: Decodable {
            let ok: Bool
        }
        let _: EffortResponse = try await post("api/mobile/model/effort", body: EffortBody(effort: effort))
    }

    func send(_ prompt: OutboundPrompt, onApproval: @escaping @Sendable (ApprovalRequest) -> Void) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        guard let baseURL else { throw HermesTransportError.notConnected }
        let body = try JSONEncoder().encode(prompt)
        var request = URLRequest(url: endpointURL(baseURL: baseURL, path: "api/mobile/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = body
        addAuth(to: &request)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesTransportError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HermesTransportError.server("Chat failed (HTTP \(http.statusCode))")
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer = Data()
                    var streamID: String?
                    var streamText = ""
                    for try await chunk in bytes {
                        buffer.append(chunk)
                        for frame in HTTPHermesTransport.extractFrames(from: &buffer) {
                            if let event = try HTTPHermesTransport.parseSSEEvent(frame) {
                                switch event.kind {
                                case .delta(let text):
                                    let id = streamID ?? "stream-\(UUID().uuidString)"
                                    streamID = id
                                    streamText += text
                                    continuation.yield(HermesMessage(id: id, role: .assistant, text: streamText, createdAt: .now, toolCalls: []))
                                case .transcript(let sessionID, let messages):
                                    _ = sessionID
                                    for message in messages where message.isTranscriptVisible {
                                        continuation.yield(message)
                                    }
                                case .approval(let id, let command, let description):
                                    onApproval(ApprovalRequest(id: id, command: command, description: description))
                                case .error(let detail):
                                    throw HermesTransportError.server(detail)
                                case .done:
                                    return
                                }
                            }
                        }
                    }
                    // Trailing frame without final blank line.
                    if !buffer.isEmpty, let event = try HTTPHermesTransport.parseSSEEvent(buffer) {
                        switch event.kind {
                        case .delta(let text):
                            let id = streamID ?? "stream-\(UUID().uuidString)"
                            streamID = id
                            streamText += text
                            continuation.yield(HermesMessage(id: id, role: .assistant, text: streamText, createdAt: .now, toolCalls: []))
                        case .transcript(_, let messages):
                            for message in messages where message.isTranscriptVisible {
                                continuation.yield(message)
                            }
                        case .approval(let id, let command, let description):
                            onApproval(ApprovalRequest(id: id, command: command, description: description))
                        case .error(let detail):
                            throw HermesTransportError.server(detail)
                        case .done:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func approve(approvalID: String, verdict: String) async throws {
        guard let baseURL else { throw HermesTransportError.notConnected }
        var request = URLRequest(url: endpointURL(baseURL: baseURL, path: "api/mobile/approvals/\(approvalID)/reply"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["verdict": verdict])
        addAuth(to: &request)
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesTransportError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HermesTransportError.server("Approval reply failed (HTTP \(http.statusCode))")
        }
    }

    /// Split a byte buffer on blank lines into complete SSE frames, leaving
    /// the unconsumed suffix in `buffer`. Safe for tiny network chunks: the
    /// suffix is re-assigned (copy-on-write) instead of mutated in place,
    /// which traps when Data stores the buffer inline and a slice is alive.
    static func extractFrames(from buffer: inout Data) -> [Data] {
        var frames: [Data] = []
        while let range = buffer.range(of: Data("\n\n".utf8)) {
            frames.append(buffer.subdata(in: buffer.startIndex..<range.lowerBound))
            buffer = buffer.subdata(in: range.upperBound..<buffer.endIndex)
        }
        return frames
    }

    /// Parse one SSE frame (bytes between blank lines) into a mobile chat event.
    static func parseSSEEvent(_ frame: Data) throws -> SSEEvent? {
        guard let text = String(data: frame, encoding: .utf8) else { return nil }
        var payload = ""
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if trimmed.hasPrefix("data:") {
                let value = trimmed.dropFirst(5)
                if value.hasPrefix(" ") {
                    payload += value.dropFirst()
                } else {
                    payload += value
                }
                payload += "\n"
            }
        }
        let json = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        switch dict["type"] as? String {
        case "delta":
            guard let text = dict["text"] as? String else { return nil }
            return SSEEvent(kind: .delta(text))
        case "transcript":
            let sessionID = dict["sessionID"] as? String
            var messages: [HermesMessage] = []
            if let raw = dict["messages"] as? [[String: Any]] {
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
                for entry in raw {
                    if let data = try? JSONSerialization.data(withJSONObject: entry),
                       let message = try? decoder.decode(HermesMessage.self, from: data) {
                        messages.append(message)
                    }
                }
            }
            return SSEEvent(kind: .transcript(sessionID, messages))
        case "error":
            return SSEEvent(kind: .error(dict["detail"] as? String ?? "Hermes chat failed"))
        case "approval":
            guard let id = dict["id"] as? String else { return nil }
            return SSEEvent(kind: .approval(
                id,
                dict["command"] as? String ?? "",
                dict["description"] as? String ?? ""
            ))
        case "done":
            return SSEEvent(kind: .done)
        default:
            return nil
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

    func renameSession(id: String, title: String) async throws {
        let _: MobileSessionActionResponse = try await post("api/mobile/sessions/\(id)/rename", body: MobileRenameRequest(title: title))
    }

    func pinSession(id: String, pinned: Bool) async throws {
        let _: MobileSessionActionResponse = try await post("api/mobile/sessions/\(id)/pin", body: MobilePinRequest(pinned: pinned))
    }

    func archiveSession(id: String) async throws {
        let _: MobileSessionActionResponse = try await post("api/mobile/sessions/\(id)/archive", body: MobileArchiveRequest(archived: true))
    }

    func attachDesktopFile(path: String) async throws -> HermesDesktopAttachment {
        try await post("api/mobile/files/attach", body: MobileDesktopFileAttachmentRequest(path: path))
    }

    func uploadAttachment(fileURL: URL) async throws -> String {
        guard let baseURL else { throw HermesTransportError.notConnected }
        let data = try Data(contentsOf: fileURL)
        let boundary = "hermes-mobile-\(UUID().uuidString)"
        let filename = fileURL.lastPathComponent.isEmpty ? "attachment.bin" : fileURL.lastPathComponent

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpointURL(baseURL: baseURL, path: "api/mobile/attachments"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        addAuth(to: &request)

        let (responseData, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HermesTransportError.server("Upload failed (HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode)))")
        }
        struct UploadResponse: Decodable { let ok: Bool; let path: String }
        do {
            let decoded = try decoder.decode(UploadResponse.self, from: responseData)
            return decoded.path
        } catch {
            throw HermesTransportError.server("Could not decode upload response")
        }
    }

    private func get<T: Decodable>(_ path: String, timeout: TimeInterval = 12) async throws -> T {
        try await dataRequest(path: path, method: "GET", body: Optional<Data>.none, timeout: timeout)
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
        // The mobile API is served by the hermes-mobile dashboard plugin
        // (mounted at /api/plugins/hermes-mobile). Keep the path segments
        // contract identical to the old standalone bridge.
        let pluginPath = path.replacingOccurrences(of: "api/mobile/", with: "api/plugins/hermes-mobile/")
        let raw = pluginPath.split(separator: "/").reduce(baseURL) { partial, component in
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

enum SSEEventKind {
    case delta(String)
    case transcript(String?, [HermesMessage])
    case approval(String, String, String)
    case error(String)
    case done
}

struct SSEEvent {
    let kind: SSEEventKind
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

private struct MobileRenameRequest: Encodable {
    let title: String
}

private struct MobilePinRequest: Encodable {
    let pinned: Bool
}

private struct MobileArchiveRequest: Encodable {
    let archived: Bool
}

private struct MobileDesktopFileAttachmentRequest: Encodable {
    let path: String
}

private struct MobileSessionActionResponse: Decodable {
    let ok: Bool
}

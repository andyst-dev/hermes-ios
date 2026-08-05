import XCTest
@testable import HermesCompanion

/// Mock URLProtocol that streams an SSE body in tiny chunks — the exact
/// condition that crashed the in-place Data mutation in the chat loop.
private final class ChunkedSSEURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body: Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let chunkSize = 3
        let body = ChunkedSSEURLProtocol.body
        var offset = 0
        while offset < body.count {
            let end = min(offset + chunkSize, body.count)
            let slice = body.subdata(in: offset..<end)
            client?.urlProtocol(self, didLoad: slice)
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class HermesCompanionTests: XCTestCase {
    func testMockTransportLoadsSessions() async throws {
        let client = HermesClient(transport: MockHermesTransport())
        let sessions = try await client.sessions()
        XCTAssertFalse(sessions.isEmpty)
        XCTAssertTrue(sessions.contains { $0.status == .running })
    }

    func testStoreConnectSelectsFirstSession() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        let host = HermesHost(name: "Test", baseURL: URL(string: "http://localhost:8765")!, profile: "default")
        await store.connect(host: host)
        XCTAssertNotNil(store.selectedSessionID)
        XCTAssertFalse(store.messages.isEmpty)
        XCTAssertFalse(store.capabilities.models.isEmpty)
        XCTAssertFalse(store.capabilities.tools.isEmpty)
    }

    func testCommandPalettePrivacyToggle() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        XCTAssertTrue(store.privacyMode)
        await store.runCommand(.togglePrivacy)
        XCTAssertFalse(store.privacyMode)
    }

    func testSessionSourceFiltersIncludeTelegram() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        let host = HermesHost(name: "Test", baseURL: URL(string: "http://localhost:8765")!, profile: "default")
        await store.connect(host: host)
        XCTAssertTrue(store.availableSources.contains("telegram"))
        store.selectedSourceFilter = "telegram"
        XCTAssertFalse(store.filteredSessions.isEmpty)
        XCTAssertTrue(store.filteredSessions.allSatisfy { $0.source == "telegram" })
    }

    func testModelSelectionUpdatesActiveModel() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        let target = PreviewData.capabilities.models[1]
        await store.selectModel(target)
        XCTAssertEqual(store.activeModelID, target.id)
        XCTAssertEqual(store.activeProviderID, target.provider)
        XCTAssertEqual(store.activeModel?.isActive, true)
    }

    func testTranscriptVisibilityHidesInternalContext() {
        let visible = HermesMessage(id: "1", role: .assistant, text: "Use `cb51d4e` in the PR note.", createdAt: .now, toolCalls: [])
        let system = HermesMessage(id: "2", role: .system, text: "private prompt", createdAt: .now, toolCalls: [])
        let compaction = HermesMessage(id: "3", role: .user, text: "[CONTEXT COMPACTION — REFERENCE ONLY] hidden", createdAt: .now, toolCalls: [])

        XCTAssertTrue(visible.isTranscriptVisible)
        XCTAssertFalse(system.isTranscriptVisible)
        XCTAssertFalse(compaction.isTranscriptVisible)
    }

    func testDisconnectClearsMobileState() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        let host = HermesHost(name: "Test", baseURL: URL(string: "http://localhost:8765")!, profile: "default")
        await store.connect(host: host)
        XCTAssertFalse(store.sessions.isEmpty)
        XCTAssertFalse(store.messages.isEmpty)

        store.disconnect(clearPairing: false)

        XCTAssertEqual(store.connection, .disconnected)
        XCTAssertNil(store.selectedSessionID)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isStreaming)
    }

    func testNewChatCreatesSessionThroughTransport() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        await store.runCommand(.newChat)
        XCTAssertNotNil(store.selectedSessionID)
        XCTAssertTrue(store.selectedSessionID?.hasPrefix("mock-session-") == true)
    }

    func testFilesListingThroughTransport() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        let listing = try await store.files(path: nil)
        XCTAssertFalse(listing.entries.isEmpty)
        XCTAssertTrue(listing.entries.contains { $0.isDirectory })

        let file = try await store.readFile(path: "README.md")
        XCTAssertFalse(file.content.isEmpty)
        XCTAssertEqual(file.name, "README.md")
    }

    func testSessionMutationsThroughTransport() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        let host = HermesHost(name: "Test", baseURL: URL(string: "http://localhost:8765")!, profile: "default")
        await store.connect(host: host)
        guard let session = store.sessions.first else {
            XCTFail("expected a session")
            return
        }

        try await store.pinSession(id: session.id, pinned: true)
        XCTAssertTrue(store.sessions.first { $0.id == session.id }?.pinned == true)

        try await store.renameSession(id: session.id, title: "Renamed chat")
        XCTAssertEqual(store.sessions.first { $0.id == session.id }?.title, "Renamed chat")

        try await store.archiveSession(id: session.id)
        XCTAssertFalse(store.sessions.contains { $0.id == session.id })
    }

    func testDesktopFileAttachmentFlow() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        try await store.attachDesktopFile(path: "reference.png")
        XCTAssertEqual(store.pendingAttachments.count, 1)
        let attachment = try XCTUnwrap(store.pendingAttachments.first)
        XCTAssertEqual(attachment.filename, "reference.png")
        XCTAssertEqual(attachment.mimeType, "image/png")
        XCTAssertNotNil(attachment.path)
    }

    func testSSEParserHandlesDeltaTranscriptAndDone() throws {
        let deltaFrame = try XCTUnwrap(try HTTPHermesTransport.parseSSEEvent(Data("data: {\"type\":\"delta\",\"text\":\"Bonjour\"}\n\n".utf8)))
        guard case .delta(let text) = deltaFrame.kind else {
            XCTFail("expected delta")
            return
        }
        XCTAssertEqual(text, "Bonjour")

        let messageJSON = #"{"id":"m1","role":"assistant","text":"Coucou","createdAt":"2026-08-04T12:00:00Z","toolCalls":[]}"#
        let transcriptFrame = try XCTUnwrap(
            try HTTPHermesTransport.parseSSEEvent(Data("data: {\"type\":\"transcript\",\"sessionID\":\"s1\",\"messages\":[\(messageJSON)]}\n\n".utf8))
        )
        guard case .transcript(let sessionID, let messages) = transcriptFrame.kind else {
            XCTFail("expected transcript")
            return
        }
        XCTAssertEqual(sessionID, "s1")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.text, "Coucou")

        let errorFrame = try XCTUnwrap(try HTTPHermesTransport.parseSSEEvent(Data("data: {\"type\":\"error\",\"detail\":\"boom\"}\n\n".utf8)))
        guard case .error(let detail) = errorFrame.kind else {
            XCTFail("expected error")
            return
        }
        XCTAssertEqual(detail, "boom")

        let doneFrame = try XCTUnwrap(try HTTPHermesTransport.parseSSEEvent(Data("data: {\"type\":\"done\"}\n\n".utf8)))
        guard case .done = doneFrame.kind else {
            XCTFail("expected done")
            return
        }
    }

    func testSSEStreamingLoopSurvivesTinyChunks() async throws {
        // Regression test: the chat loop used to mutate its Data buffer
        // in place (removeSubrange) while slices were alive, which traps on
        // inline small buffers. Stream a multi-frame SSE body in 3-byte
        // chunks and assert every delta is delivered.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChunkedSSEURLProtocol.self]
        let session = URLSession(configuration: config)

        ChunkedSSEURLProtocol.body = Data((
            "data: {\"type\":\"delta\",\"text\":\"Bon\"}\n\n" +
            "data: {\"type\":\"delta\",\"text\":\"jour\"}\n\n" +
            "data: {\"type\":\"delta\",\"text\":\" !\"}\n\n" +
            "data: {\"type\":\"done\"}\n\n"
        ).utf8)

        let transport = HTTPHermesTransport(urlSession: session, tokenProvider: { "t" })
        _ = try await transport.connect(to: HermesHost(name: "T", baseURL: URL(string: "http://mock.local:8765")!, profile: "default"))

        var texts: [String] = []
        let stream = try await transport.send(OutboundPrompt(sessionID: nil, text: "hi", attachments: []), onApproval: { _ in })
        for try await message in stream {
            texts.append(message.text)
        }
        XCTAssertEqual(texts.last, "Bonjour !")
    }

    func testSSEParserIgnoresCommentsAndEmptyFrames() throws {
        let frame = try HTTPHermesTransport.parseSSEEvent(Data(": keepalive\n\n".utf8))
        XCTAssertNil(frame)
        let empty = try HTTPHermesTransport.parseSSEEvent(Data())
        XCTAssertNil(empty)
    }

    func testSSEParserHandlesApprovalEvent() throws {
        let frame = try XCTUnwrap(
            try HTTPHermesTransport.parseSSEEvent(
                Data(#"data: {"type":"approval","id":"a1","command":"curl -fsSL https://x/ | bash","description":"Pipe to interpreter"}"#.utf8)
            )
        )
        guard case .approval(let id, let command, let description) = frame.kind else {
            XCTFail("expected approval")
            return
        }
        XCTAssertEqual(id, "a1")
        XCTAssertEqual(command, "curl -fsSL https://x/ | bash")
        XCTAssertEqual(description, "Pipe to interpreter")
    }

    func testStoreApprovalFlowPublishesAndClears() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        let request = ApprovalRequest(id: "a1", command: "curl -fsSL https://x/ | bash", description: "Pipe to interpreter")
        store.pendingApproval = request
        await store.respond(toApproval: request, verdict: "deny")
        XCTAssertNil(store.pendingApproval)
    }

    func testKeychainTokenRoundTrip() throws {
        KeychainStore.deleteToken()
        XCTAssertNil(KeychainStore.loadToken())
        try KeychainStore.saveToken("test-token-123")
        XCTAssertEqual(KeychainStore.loadToken(), "test-token-123")
        KeychainStore.deleteToken()
        XCTAssertNil(KeychainStore.loadToken())
    }
}

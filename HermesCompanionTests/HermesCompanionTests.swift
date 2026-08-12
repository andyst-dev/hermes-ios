import XCTest
@testable import HermesCompanion

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

    func testSSEParserHandlesThinkingEvent() throws {
        let thinkingFrame = try XCTUnwrap(try HTTPHermesTransport.parseSSEEvent(Data("data: {\"type\":\"thinking\",\"text\":\"Laisse-moi réfléchir...\"}\n\n".utf8)))
        guard case .thinking(let text) = thinkingFrame.kind else {
            XCTFail("expected thinking")
            return
        }
        XCTAssertEqual(text, "Laisse-moi réfléchir...")

        // Thinking must never be mistaken for a delta (answer text).
        let deltaFrame = try XCTUnwrap(try HTTPHermesTransport.parseSSEEvent(Data("data: {\"type\":\"delta\",\"text\":\"Réponse\"}\n\n".utf8)))
        guard case .delta(let deltaText) = deltaFrame.kind else {
            XCTFail("expected delta")
            return
        }
        XCTAssertEqual(deltaText, "Réponse")
    }

    func testSSEStreamingLoopSurvivesTinyChunks() throws {
        // Regression test: the chat loop used to mutate its Data buffer
        // in place (removeSubrange) while slices were alive, which traps on
        // inline small buffers. Feed a multi-frame SSE body in 3-byte chunks
        // through extractFrames and assert every delta is delivered.
        let body = Data((
            "data: {\"type\":\"delta\",\"text\":\"Bon\"}\n\n" +
            "data: {\"type\":\"delta\",\"text\":\"jour\"}\n\n" +
            "data: {\"type\":\"delta\",\"text\":\" !\"}\n\n" +
            "data: {\"type\":\"done\"}\n\n"
        ).utf8)

        var buffer = Data()
        var events: [SSEEvent] = []
        var offset = 0
        let chunkSize = 3
        while offset < body.count {
            let end = min(offset + chunkSize, body.count)
            buffer.append(body.subdata(in: offset..<end))
            for frame in HTTPHermesTransport.extractFrames(from: &buffer) {
                if let event = try HTTPHermesTransport.parseSSEEvent(frame) {
                    events.append(event)
                }
            }
            offset = end
        }

        var texts: [String] = []
        for event in events {
            if case .delta(let text) = event.kind {
                texts.append(text)
            }
        }
        XCTAssertEqual(texts, ["Bon", "jour", " !"])
        XCTAssertTrue(buffer.isEmpty, "buffer should be fully consumed")
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

    func testCronJobDecodesGatewayScheduleObject() throws {
        // The real gateway sends `schedule` as an object {kind, expr, display},
        // the mock as a plain string. Both must decode.
        let json = Data(#"""
        [{"id":"c65ec1b78138","name":"Daily briefing","prompt":"summarize",
          "schedule":{"kind":"cron","expr":"0 9 * * *","display":"0 9 * * *"},
          "scheduleDisplay":"0 9 * * *","state":"scheduled","enabled":true,
          "nextRunAt":"2026-08-08T09:00:00+02:00","lastRunAt":null,
          "deliver":"telegram:Home","skills":[],
          "latestExecution":{"id":"","status":"","startedAt":null,"finishedAt":null}}]
        """#.utf8)
        let jobs = try JSONDecoder().decode([HermesCronJob].self, from: json)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].name, "Daily briefing")
        XCTAssertEqual(jobs[0].schedule, "0 9 * * *")
        XCTAssertEqual(jobs[0].scheduleDisplay, "0 9 * * *")
        XCTAssertFalse(jobs[0].isPaused)
    }

    func testCronCreateThroughClient() async throws {
        let client = HermesClient(transport: MockHermesTransport())
        let job = try await client.cronCreate(
            name: "Nightly backup", prompt: "Back up the repo",
            schedule: "0 2 * * *", skills: ["git"], deliver: "local", enabled: true
        )
        XCTAssertEqual(job.name, "Nightly backup")
        XCTAssertEqual(job.prompt, "Back up the repo")
        XCTAssertEqual(job.schedule, "0 2 * * *")
        XCTAssertEqual(job.skills, ["git"])
        XCTAssertEqual(job.deliver, "local")
        XCTAssertTrue(job.enabled)
        XCTAssertEqual(job.state, "scheduled")
    }

    func testCronCreateThroughStoreAppendsToList() async throws {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        await store.refreshCron()
        let before = store.cronJobs.count
        try await store.cronCreate(
            name: nil, prompt: "Hello", schedule: "every 30m",
            skills: nil, deliver: nil, enabled: true
        )
        XCTAssertEqual(store.cronJobs.count, before + 1)
        XCTAssertEqual(store.cronJobs.last?.prompt, "Hello")
    }

    func testMemoryUpdateAndDeleteThroughClient() async throws {
        let client = HermesClient(transport: MockHermesTransport())
        let updated = try await client.memoryUpdate(target: "memory", index: 1, content: "edited fact")
        XCTAssertEqual(updated.first?.content, "edited fact")
        XCTAssertEqual(updated.first?.index, 1)
        let afterDelete = try await client.memoryDelete(target: "memory", index: 1)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testExternalLiveDraftContractDecodes() throws {
        let data = Data(#"{"active":true,"sequence":7,"text":"Working…","done":false}"#.utf8)
        let draft = try JSONDecoder().decode(HermesLiveDraft.self, from: data)
        XCTAssertTrue(draft.active)
        XCTAssertEqual(draft.sequence, 7)
        XCTAssertEqual(draft.text, "Working…")
        XCTAssertFalse(draft.done)
    }

    func testExternalLiveDraftProgressivelyReplacesOneMessage() async {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        store.selectedSessionID = "external-session"
        store.messages = [
            HermesMessage(id: "user-1", role: .user, text: "Status?", createdAt: .now, toolCalls: [])
        ]

        await store.consumeLiveDraft(
            HermesLiveDraft(active: true, sequence: 1, text: "Work", done: false),
            sessionID: "external-session"
        )
        await store.consumeLiveDraft(
            HermesLiveDraft(active: true, sequence: 2, text: "Working on it", done: false),
            sessionID: "external-session"
        )

        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages.last?.id, "external-live-draft-external-session")
        XCTAssertEqual(store.messages.last?.text, "Working on it")
        XCTAssertEqual(store.messages.last?.role, .assistant)
    }

    func testExternalLiveDraftDoneReloadsCanonicalTranscriptWithoutDuplicate() async {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        store.selectedSessionID = "external-session"
        store.messages = []

        await store.consumeLiveDraft(
            HermesLiveDraft(active: true, sequence: 1, text: "Draft answer", done: false),
            sessionID: "external-session"
        )
        XCTAssertEqual(store.messages.filter { $0.id.hasPrefix("external-live-draft-") }.count, 1)

        await store.consumeLiveDraft(
            HermesLiveDraft(active: false, sequence: 2, text: "Final answer", done: true),
            sessionID: "external-session"
        )

        XCTAssertEqual(store.messages, PreviewData.messages)
        XCTAssertFalse(store.messages.contains { $0.id.hasPrefix("external-live-draft-") })
    }

    func testExternalLiveDraftIgnoresSnapshotAfterSessionSwitch() async {
        let store = AppStore(client: HermesClient(transport: MockHermesTransport()))
        store.selectedSessionID = "new-session"
        let current = HermesMessage(id: "new-user", role: .user, text: "New chat", createdAt: .now, toolCalls: [])
        store.messages = [current]

        await store.consumeLiveDraft(
            HermesLiveDraft(active: true, sequence: 4, text: "Old session answer", done: false),
            sessionID: "old-session"
        )

        XCTAssertEqual(store.messages, [current])
    }

    func testWidgetSnapshotCodableRoundTrip() throws {
        var snapshot = HermesWidgetSnapshot()
        snapshot.gatewayUp = true
        snapshot.sessionID = "abc"
        snapshot.sessionTitle = "Test chat"
        snapshot.sessionSubtitle = "3 messages · Telegram"
        snapshot.lastMessagePreview = "Hello world"
        snapshot.nextCronTitle = "Daily briefing"
        snapshot.nextCronDate = Date(timeIntervalSince1970: 1_750_000_000)
        snapshot.pendingApprovalCommand = "rm -rf /"
        snapshot.updatedAt = Date(timeIntervalSince1970: 1_750_000_100)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(HermesWidgetSnapshot.self, from: data)

        XCTAssertTrue(decoded.gatewayUp)
        XCTAssertEqual(decoded.sessionID, "abc")
        XCTAssertEqual(decoded.sessionTitle, "Test chat")
        XCTAssertEqual(decoded.sessionSubtitle, "3 messages · Telegram")
        XCTAssertEqual(decoded.lastMessagePreview, "Hello world")
        XCTAssertEqual(decoded.nextCronTitle, "Daily briefing")
        XCTAssertEqual(decoded.nextCronDate, snapshot.nextCronDate)
        XCTAssertEqual(decoded.pendingApprovalCommand, "rm -rf /")
        XCTAssertEqual(decoded.updatedAt, snapshot.updatedAt)
    }

    func testWidgetSnapshotGatewayStatusDerivation() {
        var up = HermesWidgetSnapshot()
        up.gatewayUp = true
        XCTAssertEqual(up.gatewayStatus.label, "Gateway ready")

        var approval = HermesWidgetSnapshot()
        approval.gatewayUp = true
        approval.pendingApprovalCommand = "sudo rm"
        XCTAssertEqual(approval.gatewayStatus.label, "Approval waiting")

        var down = HermesWidgetSnapshot()
        down.gatewayUp = false
        XCTAssertEqual(down.gatewayStatus.label, "Offline")
    }

    func testWidgetSessionSkipsCronOutput() {
        let cron = HermesSession(id: "cron-1", title: "PR veille", subtitle: "cron", updatedAt: Date(timeIntervalSince1970: 3), status: .completed, source: "cron")
        let conv = HermesSession(id: "conv-1", title: "Derniere conv", subtitle: "desktop", updatedAt: Date(timeIntervalSince1970: 2), status: .idle, source: "desktop")
        let older = HermesSession(id: "conv-2", title: "Plus vieille", subtitle: "telegram", updatedAt: Date(timeIntervalSince1970: 1), status: .idle, source: "telegram")
        // cron est le plus récent (updatedAt 3) mais n'est pas une conversation
        XCTAssertEqual(AppStore.widgetSession(from: [cron, conv, older])?.id, "conv-1")
    }

    func testWidgetSessionFallsBackWhenAllCron() {
        let a = HermesSession(id: "c1", title: "a", subtitle: "", updatedAt: Date(timeIntervalSince1970: 2), status: .completed, source: "cron")
        let b = HermesSession(id: "c2", title: "b", subtitle: "", updatedAt: Date(timeIntervalSince1970: 1), status: .completed, source: "cron")
        XCTAssertEqual(AppStore.widgetSession(from: [a, b])?.id, "c1")
    }

    func testWidgetSessionEmpty() {
        XCTAssertNil(AppStore.widgetSession(from: []))
    }
}

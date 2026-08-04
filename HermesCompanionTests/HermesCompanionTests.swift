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
}

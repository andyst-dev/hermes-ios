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
    }
}

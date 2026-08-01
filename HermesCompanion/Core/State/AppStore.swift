import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var connection: HermesConnectionState = .disconnected
    @Published var sessions: [HermesSession] = []
    @Published var selectedSessionID: String?
    @Published var messages: [HermesMessage] = []
    @Published var composerText: String = ""
    @Published var isStreaming = false

    private let client: HermesClient

    init(client: HermesClient) {
        self.client = client
    }

    var selectedSession: HermesSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    func connect(host: HermesHost) async {
        connection = .connecting
        do {
            let connectedHost = try await client.connect(host: host)
            connection = .connected(connectedHost)
            try await refreshSessions()
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    func refreshSessions() async throws {
        sessions = try await client.sessions()
        if selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }
        if let selectedSessionID {
            messages = try await client.messages(sessionID: selectedSessionID)
        }
    }

    func select(session: HermesSession) async {
        selectedSessionID = session.id
        do {
            messages = try await client.messages(sessionID: session.id)
        } catch {
            messages = [HermesMessage(id: UUID(), role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: [])]
        }
    }

    func sendComposer() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""
        let userMessage = HermesMessage(id: UUID(), role: .user, text: text, createdAt: .now, toolCalls: [])
        messages.append(userMessage)
        isStreaming = true

        do {
            let stream = try await client.send(OutboundPrompt(sessionID: selectedSessionID, text: text, attachments: []))
            for try await update in stream {
                if let index = messages.lastIndex(where: { $0.id == update.id }) {
                    messages[index] = update
                } else {
                    messages.append(update)
                }
            }
        } catch {
            messages.append(HermesMessage(id: UUID(), role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
        }
        isStreaming = false
    }

    func stop() async {
        guard let selectedSessionID else { return }
        do { try await client.stop(sessionID: selectedSessionID) } catch {}
        isStreaming = false
    }
}

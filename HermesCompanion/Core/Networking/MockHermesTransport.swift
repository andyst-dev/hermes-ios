import Foundation

struct MockHermesTransport: HermesTransport {
    func connect(to host: HermesHost) async throws -> HermesHost {
        try await Task.sleep(for: .milliseconds(350))
        return host
    }

    func fetchSessions() async throws -> [HermesSession] {
        PreviewData.sessions
    }

    func fetchMessages(sessionID: String) async throws -> [HermesMessage] {
        PreviewData.messages
    }

    func send(_ prompt: OutboundPrompt) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chunks = [
                    "Je lance ça proprement.",
                    "\n\nJe vais vérifier le contexte, patcher minimalement, puis lancer les tests.",
                    "\n\nEnsuite je prépare un PR body clean sans chemins locaux ni secrets."
                ]
                var current = HermesMessage(
                    id: UUID(),
                    role: .assistant,
                    text: "",
                    createdAt: .now,
                    toolCalls: [
                        HermesToolCall(id: UUID(), name: "terminal", command: "git diff --check", status: .running, summary: "Validating patch hygiene")
                    ]
                )
                for chunk in chunks {
                    try await Task.sleep(for: .milliseconds(260))
                    current.text += chunk
                    continuation.yield(current)
                }
                current.toolCalls[0].status = .succeeded
                current.toolCalls[0].summary = "No whitespace errors"
                continuation.yield(current)
                continuation.finish()
            }
        }
    }

    func stop(sessionID: String) async throws {}
}

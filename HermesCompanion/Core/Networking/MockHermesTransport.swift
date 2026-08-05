import Foundation

final class MockHermesTransport: HermesTransport, @unchecked Sendable {
    private var sessionList: [HermesSession] = PreviewData.sessions

    func connect(to host: HermesHost) async throws -> HermesHost {
        try await Task.sleep(for: .milliseconds(350))
        return host
    }

    func fetchSessions() async throws -> [HermesSession] {
        sessionList
    }

    func fetchMessages(sessionID: String) async throws -> [HermesMessage] {
        PreviewData.messages
    }

    func fetchCapabilities() async throws -> HermesCapabilitySnapshot {
        PreviewData.capabilities
    }

    func fetchModels() async throws -> [HermesModel] {
        PreviewData.capabilities.models
    }

    func selectModel(provider: String, model: String) async throws {}

    func fetchReasoningEffort() async throws -> HermesReasoningEffort {
        HermesReasoningEffort(effort: "medium", options: HermesReasoningEffort.defaultOptions)
    }

    func setReasoningEffort(_ effort: String) async throws {}

    func newChat() async throws -> String {
        "mock-session-\(UUID().uuidString.prefix(8))"
    }

    func fetchFiles(path: String?) async throws -> HermesFileListing {
        HermesFileListing(
            path: path ?? "",
            entries: [
                HermesFileEntry(name: "reference.png", path: "reference.png", isDirectory: false, size: 512, mtime: nil, mimeType: "image/png"),
                HermesFileEntry(name: "README.md", path: "README.md", isDirectory: false, size: 512, mtime: nil, mimeType: "text/markdown"),
                HermesFileEntry(name: "projects", path: "projects", isDirectory: true, size: nil, mtime: nil, mimeType: nil),
            ]
        )
    }

    func readFile(path: String) async throws -> HermesFileContent {
        HermesFileContent(name: path, content: "# Mock file\n\nThis is demo content.", truncated: false)
    }

    func renameSession(id: String, title: String) async throws {
        if let index = sessionList.firstIndex(where: { $0.id == id }) {
            sessionList[index].title = title
        }
    }

    func pinSession(id: String, pinned: Bool) async throws {
        if let index = sessionList.firstIndex(where: { $0.id == id }) {
            sessionList[index].pinned = pinned
        }
    }

    func archiveSession(id: String) async throws {
        sessionList.removeAll { $0.id == id }
    }

    func uploadAttachment(fileURL: URL) async throws -> String {
        "/mock/\(fileURL.lastPathComponent)"
    }

    func attachDesktopFile(path: String) async throws -> HermesDesktopAttachment {
        HermesDesktopAttachment(id: UUID(), name: URL(fileURLWithPath: path).lastPathComponent, path: "/mock/\(path)", mimeType: "image/png", sizeBytes: 512)
    }

    func send(_ prompt: OutboundPrompt, onApproval: @escaping @Sendable (ApprovalRequest) -> Void) async throws -> AsyncThrowingStream<HermesMessage, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chunks = [
                    "Je lance ça proprement.",
                    "\n\nJe vais vérifier le contexte, patcher minimalement, puis lancer les tests.",
                    "\n\nEnsuite je prépare un PR body clean sans chemins locaux ni secrets."
                ]
                var current = HermesMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    text: "",
                    createdAt: .now,
                    toolCalls: [
                        HermesToolCall(id: UUID().uuidString, name: "terminal", command: "git diff --check", status: .running, summary: "Validating patch hygiene")
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

    func approve(approvalID: String, verdict: String) async throws {}

    func stop(sessionID: String) async throws {}
}

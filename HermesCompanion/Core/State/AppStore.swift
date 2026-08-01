import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var connection: HermesConnectionState = .disconnected
    @Published var sessions: [HermesSession] = []
    @Published var selectedSessionID: String?
    @Published var messages: [HermesMessage] = []
    @Published var composerText: String = ""
    @Published var isStreaming = false
    @Published var capabilities = PreviewData.capabilities
    @Published var activeModelID = PreviewData.capabilities.models.first?.id
    @Published var activeProviderID = PreviewData.capabilities.models.first?.provider
    @Published var selectedSourceFilter: String = "all"
    @Published var privacyMode = true

    private let client: HermesClient

    init(client: HermesClient) {
        self.client = client
    }

    var selectedSession: HermesSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    var activeModel: HermesModel? {
        capabilities.models.first { $0.id == activeModelID && ($0.provider == activeProviderID || activeProviderID == nil) }
    }

    var availableSources: [String] {
        let sources = Set(sessions.compactMap { $0.source?.lowercased() }.filter { !$0.isEmpty })
        return ["all"] + sources.sorted()
    }

    var filteredSessions: [HermesSession] {
        guard selectedSourceFilter != "all" else { return sessions }
        return sessions.filter { ($0.source ?? "").lowercased() == selectedSourceFilter }
    }

    var terminalLines: [TerminalLine] {
        messages.flatMap { message in
            var lines: [TerminalLine] = []
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(TerminalLine(kind: message.role == .user ? .input : .output, text: text))
            }
            for tool in message.toolCalls {
                if let command = tool.command, !command.isEmpty {
                    lines.append(TerminalLine(kind: .command, text: command))
                }
                lines.append(TerminalLine(kind: .status, text: "\(tool.name): \(tool.summary)"))
            }
            return lines
        }
    }

    func connect(host: HermesHost) async {
        connection = .connecting
        do {
            let connectedHost = try await client.connect(host: host)
            connection = .connected(connectedHost)
            try await refreshSessions()
            try await refreshCapabilities()
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

    func refreshCapabilities() async throws {
        capabilities = try await client.capabilities()
        let models = try? await client.models()
        if let models, !models.isEmpty {
            capabilities.models = models
        }
        if let active = capabilities.models.first(where: { $0.isActive == true }) ?? capabilities.models.first {
            activeModelID = active.id
            activeProviderID = active.provider
        }
    }

    func selectModel(_ model: HermesModel) async {
        do {
            try await client.selectModel(provider: model.provider, model: model.id)
            activeModelID = model.id
            activeProviderID = model.provider
            capabilities.models = capabilities.models.map { existing in
                var copy = existing
                copy.isActive = existing.id == model.id && existing.provider == model.provider
                return copy
            }
        } catch {
            messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
        }
    }

    func select(session: HermesSession) async {
        selectedSessionID = session.id
        do {
            messages = try await client.messages(sessionID: session.id)
        } catch {
            messages = [HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: [])]
        }
    }

    func sendComposer() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""
        let userMessage = HermesMessage(id: UUID().uuidString, role: .user, text: text, createdAt: .now, toolCalls: [])
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
            messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
        }
        isStreaming = false
    }

    func stop() async {
        guard let selectedSessionID else { return }
        do { try await client.stop(sessionID: selectedSessionID) } catch {}
        isStreaming = false
    }

    func runCommand(_ command: MobileCommand) async {
        switch command {
        case .newChat:
            selectedSessionID = nil
            messages = []
        case .stop:
            await stop()
        case .continueLast:
            composerText = "Continue"
            await sendComposer()
        case .togglePrivacy:
            privacyMode.toggle()
        case .refresh:
            try? await refreshSessions()
            try? await refreshCapabilities()
        }
    }
}

enum MobileCommand: String, CaseIterable, Identifiable {
    case newChat
    case stop
    case continueLast
    case togglePrivacy
    case refresh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newChat: "New chat"
        case .stop: "Stop running turn"
        case .continueLast: "Continue last task"
        case .togglePrivacy: "Toggle privacy mode"
        case .refresh: "Refresh desktop state"
        }
    }

    var icon: String {
        switch self {
        case .newChat: "plus.message"
        case .stop: "stop.fill"
        case .continueLast: "arrow.clockwise"
        case .togglePrivacy: "eye.slash"
        case .refresh: "arrow.triangle.2.circlepath"
        }
    }
}

struct TerminalLine: Identifiable, Equatable {
    let id = UUID()
    var kind: Kind
    var text: String

    enum Kind: Equatable {
        case input
        case output
        case command
        case status
    }
}

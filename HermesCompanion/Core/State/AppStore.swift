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
    @Published var pendingAttachments: [OutboundPrompt.Attachment] = []

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
        // Model discovery is independent from the lightweight capability snapshot.
        // Do it first: a capabilities failure must never collapse the picker back
        // to its single bundled preview model.
        let discoveredModels = try await client.models()
        if !discoveredModels.isEmpty {
            capabilities.models = discoveredModels
        }
        if let snapshot = try? await client.capabilities() {
            var merged = snapshot
            merged.models = capabilities.models
            capabilities = merged
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
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        composerText = ""
        let userMessage = HermesMessage(id: UUID().uuidString, role: .user, text: text, createdAt: .now, toolCalls: [])
        messages.append(userMessage)
        isStreaming = true

        do {
            var attachments = pendingAttachments
            pendingAttachments = []
            for index in attachments.indices {
                if attachments[index].path == nil {
                    if let uploaded = try? await client.uploadAttachment(fileURL: attachmentFileURL(for: attachments[index])) {
                        attachments[index].path = uploaded
                    }
                }
            }
            let stream = try await client.send(OutboundPrompt(sessionID: selectedSessionID, text: text, attachments: attachments))
            for try await update in stream {
                if let index = messages.lastIndex(where: { $0.id == update.id }) {
                    messages[index] = update
                } else {
                    messages.append(update)
                }
            }
            try? await refreshSessions()
        } catch {
            messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
        }
        isStreaming = false
    }

    func addPendingAttachment(_ attachment: OutboundPrompt.Attachment) {
        pendingAttachments.append(attachment)
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func attachDesktopFile(path: String) async throws {
        let attached = try await client.attachDesktopFile(path: path)
        pendingAttachments.append(
            OutboundPrompt.Attachment(
                id: attached.id,
                filename: attached.name,
                mimeType: attached.mimeType,
                sizeBytes: attached.sizeBytes,
                path: attached.path
            )
        )
    }

    private func attachmentFileURL(for attachment: OutboundPrompt.Attachment) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(attachment.filename)
    }

    func stop() async {
        guard let selectedSessionID else { return }
        do { try await client.stop(sessionID: selectedSessionID) } catch {}
        isStreaming = false
    }

    func disconnect(clearPairing: Bool = false) {
        connection = .disconnected
        selectedSessionID = nil
        sessions = []
        messages = []
        isStreaming = false
        if clearPairing {
            KeychainStore.deleteToken()
            UserDefaults.standard.removeObject(forKey: "hermes.host")
            UserDefaults.standard.removeObject(forKey: "hermes.profile")
        }
    }

    func files(path: String? = nil) async throws -> HermesFileListing {
        try await client.files(path: path)
    }

    func readFile(path: String) async throws -> HermesFileContent {
        try await client.readFile(path: path)
    }

    func renameSession(id: String, title: String) async throws {
        try await client.renameSession(id: id, title: title)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].title = title
        }
        try? await refreshSessions()
    }

    func pinSession(id: String, pinned: Bool) async throws {
        try await client.pinSession(id: id, pinned: pinned)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].pinned = pinned
        }
        try? await refreshSessions()
    }

    func archiveSession(id: String) async throws {
        try await client.archiveSession(id: id)
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = nil
            messages = []
        }
        try? await refreshSessions()
    }

    func runCommand(_ command: MobileCommand) async {
        switch command {
        case .newChat:
            do {
                let sessionID = try await client.newChat()
                selectedSessionID = sessionID
                messages = []
                try? await refreshSessions()
            } catch {
                messages.append(HermesMessage(id: UUID().uuidString, role: .system, text: error.localizedDescription, createdAt: .now, toolCalls: []))
            }
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

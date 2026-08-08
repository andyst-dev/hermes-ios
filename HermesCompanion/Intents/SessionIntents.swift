import AppIntents
import Foundation

/// Shared plumbing for the Siri intents: same host + token resolution as
/// the app (UserDefaults + Keychain), so they work standalone.
@MainActor
private func makeIntentClient() async -> HermesClient? {
    guard KeychainStore.loadToken() != nil else { return nil }
    let storedHost = UserDefaults.standard.string(forKey: "hermes.host")
    let hostURL = storedHost.flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:8765")!
    let transport: any HermesTransport = HTTPHermesTransport(tokenProvider: {
        KeychainStore.loadToken()
    })
    let client = HermesClient(transport: transport)
    let host = HermesHost(
        name: "Desktop Hermes",
        baseURL: hostURL,
        profile: UserDefaults.standard.string(forKey: "hermes.profile") ?? "default"
    )
    guard (try? await client.connect(host: host)) != nil else { return nil }
    return client
}

private func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, HH:mm"
    return formatter.string(from: date)
}

/// "Hey Siri, list my Hermes sessions" — speaks the most recent sessions.
struct ListSessionsIntent: AppIntent {
    static var title: LocalizedStringResource { "List Hermes sessions" }
    static var description: IntentDescription {
        IntentDescription("Lists your most recent Hermes sessions on the Desktop.")
    }

    @Parameter(title: "How many", description: "Number of sessions to list (default 8)")
    var count: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let client = await makeIntentClient() else {
            return .result(dialog: IntentDialog(stringLiteral: "Hermes is not paired. Open the app and scan the Desktop QR code first."))
        }
        let sessions = (try? await client.sessions()) ?? []
        let top = sessions.prefix(max(1, min(count ?? 8, 12)))
        guard !top.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "No Hermes sessions yet."))
        }
        let dialog = top.map { "\($0.title) · \(shortDate($0.updatedAt))" }.joined(separator: "\n")
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// "Hey Siri, open my Hermes session …" — finds the session by title and
/// opens the app on that conversation.
struct OpenSessionIntent: AppIntent {
    static var title: LocalizedStringResource { "Open a Hermes session" }
    static var description: IntentDescription {
        IntentDescription("Opens a Hermes conversation on your iPhone.")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Session title", description: "Full or partial title of the conversation")
    var title: String

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let client = await makeIntentClient() else {
            return .result()
        }
        let sessions = (try? await client.sessions()) ?? []
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = sessions.first(where: {
            $0.title.lowercased().contains(wanted) || wanted.contains($0.title.lowercased())
        }) else {
            return .result()
        }
        // The app reads this after launch and opens the conversation.
        UserDefaults.standard.set(match.id, forKey: "hermes.pendingOpenSessionID")
        return .result()
    }
}

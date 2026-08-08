import AppIntents
import Foundation

/// "Hey Siri, ask Hermes to …" — sends a prompt to the Desktop agent and
/// returns its answer as the spoken dialog. Reuses the same host + token as
/// the app (UserDefaults + Keychain), so it works standalone, without any
/// paid Apple account.
struct AskHermesIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Hermes"
    static var description = IntentDescription("Send a prompt to the Hermes agent on your Desktop and get its answer.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Prompt", description: "What you want Hermes to do")
    var prompt: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard KeychainStore.loadToken() != nil else {
            return .result(dialog: "Hermes is not paired. Open the app and scan the Desktop QR code first.")
        }

        // Same host resolution as the app: stored host, else the dev default.
        let storedHost = UserDefaults.standard.string(forKey: "hermes.host")
        let hostURL = storedHost.flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:8765")!
        let profile = UserDefaults.standard.string(forKey: "hermes.profile") ?? "default"
        let transport = HTTPHermesTransport()
        _ = try? await transport.connect(to: HermesHost(name: "Desktop Hermes", baseURL: hostURL, profile: profile))
        let client = HermesClient(transport: transport)

        let sessionID = try await client.newChat()
        var reply = ""
        let stream = try await client.send(OutboundPrompt(sessionID: sessionID, text: prompt, attachments: [])) { _ in }
        for try await message in stream {
            if message.role == .assistant {
                reply += message.text
            }
        }

        let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return .result(dialog: answer.isEmpty ? "Hermes is done. Open the app to read the full answer." : answer)
    }
}

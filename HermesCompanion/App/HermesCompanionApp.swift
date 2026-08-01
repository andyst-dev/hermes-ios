import SwiftUI

@main
struct HermesCompanionApp: App {
    @StateObject private var store: AppStore
    private let demoMode: Bool

    init() {
        let env = ProcessInfo.processInfo.environment
        let isDemo = env["HERMES_DEMO_CONNECTED"] == "1"
        demoMode = isDemo
        let transport: any HermesTransport = isDemo
            ? MockHermesTransport()
            : HTTPHermesTransport(tokenProvider: { KeychainStore.loadToken() })
        _store = StateObject(wrappedValue: AppStore(client: HermesClient(transport: transport)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    guard demoMode else { return }
                    await store.connect(host: HermesHost(name: "Desktop Hermes", baseURL: URL(string: "http://127.0.0.1:8765")!, profile: "default"))
                }
        }
    }
}

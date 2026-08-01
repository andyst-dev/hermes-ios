import SwiftUI

@main
struct HermesCompanionApp: App {
    @StateObject private var store: AppStore
    private let demoMode: Bool
    private let autoConnectHost: HermesHost?

    init() {
        let env = ProcessInfo.processInfo.environment
        let isDemo = env["HERMES_DEMO_CONNECTED"] == "1"
        demoMode = isDemo
        let envHost = env["HERMES_MOBILE_BASE_URL"].flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:8765")
        let envProfile = env["HERMES_PROFILE"] ?? "default"
        autoConnectHost = env["HERMES_DASHBOARD_SESSION_TOKEN"] == nil ? nil : HermesHost(name: "Desktop Hermes", baseURL: envHost!, profile: envProfile)
        let transport: any HermesTransport = isDemo
            ? MockHermesTransport()
            : HTTPHermesTransport(tokenProvider: {
                ProcessInfo.processInfo.environment["HERMES_DASHBOARD_SESSION_TOKEN"] ?? KeychainStore.loadToken()
            })
        _store = StateObject(wrappedValue: AppStore(client: HermesClient(transport: transport)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    if demoMode {
                        await store.connect(host: HermesHost(name: "Desktop Hermes", baseURL: URL(string: "http://127.0.0.1:8765")!, profile: "default"))
                    } else if let autoConnectHost {
                        await store.connect(host: autoConnectHost)
                    }
                }
        }
    }
}

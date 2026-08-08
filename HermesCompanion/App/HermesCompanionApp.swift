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
        let storedHost = UserDefaults.standard.string(forKey: "hermes.host")
        let storedProfile = UserDefaults.standard.string(forKey: "hermes.profile")
        let hostURL = (env["HERMES_MOBILE_BASE_URL"] ?? storedHost).flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:8765")!
        let profile = env["HERMES_PROFILE"] ?? storedProfile ?? "default"
        // Dev loop convenience: when launched with an env token (simctl), persist
        // it like a manual connect would, so a later plain icon launch reconnects
        // from Keychain instead of landing on the Connect screen. A paired token
        // already in Keychain is never clobbered.
        if let envToken = env["HERMES_DASHBOARD_SESSION_TOKEN"], KeychainStore.loadToken() == nil {
            do {
                try KeychainStore.saveToken(envToken)
                print("HERMES: persisted env token to keychain")
            } catch {
                print("HERMES: keychain save failed: \(error.localizedDescription)")
            }
            UserDefaults.standard.set(hostURL.absoluteString, forKey: "hermes.host")
            UserDefaults.standard.set(profile, forKey: "hermes.profile")
        }
        print("HERMES: hasToken=\(env["HERMES_DASHBOARD_SESSION_TOKEN"] != nil || KeychainStore.loadToken() != nil) host=\(hostURL.absoluteString)")
        let hasToken = env["HERMES_DASHBOARD_SESSION_TOKEN"] != nil || KeychainStore.loadToken() != nil
        // Debug toggle (Settings → Debug): skip the Connect screen and always
        // open the local dev desktop at 127.0.0.1:8765 on launch.
        let debugAutoConnect = UserDefaults.standard.bool(forKey: "hermes.debugAutoConnect")
        autoConnectHost = (hasToken || debugAutoConnect) ? HermesHost(name: "Desktop Hermes", baseURL: hostURL, profile: profile) : nil
        let transport: any HermesTransport = isDemo
            ? MockHermesTransport()
            : HTTPHermesTransport(tokenProvider: {
                ProcessInfo.processInfo.environment["HERMES_DASHBOARD_SESSION_TOKEN"] ?? KeychainStore.loadToken()
            })
        _store = StateObject(wrappedValue: AppStore(client: HermesClient(transport: transport)))
        NotificationManager.shared.register()
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
                .onOpenURL { url in
                    store.handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Foreground auto-refresh lives in AppStore; keep it honest about
            // whether the app is actually on screen.
            store.isAppActive = (phase == .active)
            if phase == .active {
                // Face ID lock re-arms when the app comes back to the foreground.
                store.lockNow()
            }
            if phase == .background {
                NotificationManager.shared.scheduleBackgroundCheck()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
}

import SwiftUI
import UIKit

@main
struct HermesCompanionApp: App {
    @StateObject private var store: AppStore
    @ObservedObject private var theme = ThemeManager.shared
    private let demoMode: Bool
    private let autoConnectHost: HermesHost?

    init() {
        // SwiftUI's `.tint` is not consistently forwarded to the native
        // UIRefreshControl hosted inside ScrollView. Set the Ember cream
        // directly so pull-to-refresh never falls back to system white.
        UIRefreshControl.appearance().tintColor = UIColor(
            red: 0.851,
            green: 0.659,
            blue: 0.471,
            alpha: 1
        )
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
                .environmentObject(theme)
                .preferredColorScheme(theme.mode == .cream ? .light : .dark)
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
            // NOTE: no re-lock on foreground. Re-arming on every .active was
            // unusable on a real device: the Face ID/passcode prompt itself
            // sends the app inactive→active, so unlocking re-triggered the
            // lock and the app locked again the moment it opened. The lock
            // now only arms on cold launch (AppStore.configureLockIfNeeded).
            if phase == .background {
                // Remember an in-flight turn so a later background check can
                // alert "reply ready" once the desktop finishes it.
                if store.isStreaming {
                    NotificationManager.shared.markPendingTurn(sessionID: store.selectedSessionID)
                }
                NotificationManager.shared.scheduleBackgroundCheck()
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
}

import SwiftUI

@main
struct HermesCompanionApp: App {
    @StateObject private var store = AppStore(client: HermesClient(transport: MockHermesTransport()))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    guard ProcessInfo.processInfo.environment["HERMES_DEMO_CONNECTED"] == "1" else { return }
                    await store.connect(host: HermesHost(name: "Desktop Hermes", baseURL: URL(string: "http://macbook.local:8765")!, profile: "default"))
                }
        }
    }
}

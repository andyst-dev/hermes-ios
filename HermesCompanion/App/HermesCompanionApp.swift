import SwiftUI

@main
struct HermesCompanionApp: App {
    @StateObject private var store = AppStore(client: HermesClient(transport: MockHermesTransport()))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

import SwiftUI

@main
struct PrivateMomentsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TimelineStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    await store.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        return
                    }

                    Task {
                        await store.syncPendingWorkIfNeeded()
                    }
                }
        }
    }
}

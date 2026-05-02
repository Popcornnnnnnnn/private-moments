import SwiftUI

@main
struct PrivateMomentsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TimelineStore()
    @StateObject private var playbackCenter = MediaPlaybackCenter()
    @StateObject private var videoAutoplayCenter = TimelineVideoAutoplayCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(playbackCenter)
                .environmentObject(videoAutoplayCenter)
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

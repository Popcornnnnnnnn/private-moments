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
                .preferredColorScheme(store.appAppearanceMode.colorScheme)
                .task {
                    await store.bootstrap()
                    presentShareImportIfNeeded()
                }
                .onOpenURL { url in
                    handleOpenURL(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        return
                    }

                    presentShareImportIfNeeded()

                    Task {
                        await store.syncPendingWorkIfNeeded()
                    }
                }
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.scheme == ShareImportConstants.urlScheme else {
            return
        }
        presentShareImportIfNeeded(force: true)
    }

    private func presentShareImportIfNeeded(force: Bool = false) {
        guard force || ShareImportInbox.hasPendingImports() else {
            return
        }

        NotificationCenter.default.post(name: .presentComposerForShareImport, object: nil)
    }
}

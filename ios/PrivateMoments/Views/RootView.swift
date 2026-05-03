import SwiftUI

struct RootView: View {
    @State private var isShareImportComposerPresented = false

    var body: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "rectangle.stack")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .sheet(isPresented: $isShareImportComposerPresented) {
            ComposerView()
        }
        .task {
            presentShareImportComposerIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentComposerForShareImport)) { _ in
            presentShareImportComposerIfNeeded(force: true)
        }
    }

    private func presentShareImportComposerIfNeeded(force: Bool = false) {
        guard force || ShareImportInbox.hasPendingImports() else {
            return
        }
        isShareImportComposerPresented = true
    }
}

import SwiftUI

struct RootView: View {
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
    }
}


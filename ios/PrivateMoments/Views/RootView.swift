import SwiftUI

struct RootView: View {
    @Environment(\.appLanguage) private var appLanguage
    @EnvironmentObject private var playbackCenter: MediaPlaybackCenter
    @State private var selectedTab: RootTab = .timeline
    @State private var calendarTimelineRoute: CalendarTimelineRoute?
    @State private var isShareImportComposerPresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(
                calendarRoute: $calendarTimelineRoute,
                onOpenSettings: { presentSettings() }
            )
                .tabItem {
                    Label(L10n.t("Timeline", appLanguage), systemImage: "rectangle.stack")
                }
                .tag(RootTab.timeline)

            CalendarView(
                onSelectDay: { route in
                    playbackCenter.pause()
                    calendarTimelineRoute = route
                    selectedTab = .timeline
                },
                onOpenSettings: { presentSettings() }
            )
                .tabItem {
                    Label(L10n.t("Calendar", appLanguage), systemImage: "calendar")
                }
                .tag(RootTab.calendar)

            CheckInsView()
                .tabItem {
                    Label(L10n.t("Check-ins", appLanguage), systemImage: "checkmark.circle")
                }
                .tag(RootTab.checkIns)
        }
        .sheet(isPresented: $isShareImportComposerPresented) {
            ComposerView()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .task {
            presentShareImportComposerIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentComposerForShareImport)) { _ in
            presentShareImportComposerIfNeeded(force: true)
        }
        .onChange(of: selectedTab) { _, _ in
            playbackCenter.pause()
        }
    }

    private func presentShareImportComposerIfNeeded(force: Bool = false) {
        guard force || ShareImportInbox.hasPendingImports() else {
            return
        }
        playbackCenter.pause()
        isShareImportComposerPresented = true
    }

    private func presentSettings() {
        playbackCenter.pause()
        isSettingsPresented = true
    }
}

private enum RootTab: Hashable {
    case timeline
    case calendar
    case checkIns
}

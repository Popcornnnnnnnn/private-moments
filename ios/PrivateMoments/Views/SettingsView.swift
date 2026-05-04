import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("Connection", appLanguage)) {
                    NavigationLink {
                        ServerDeviceSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("Server & Device", appLanguage))
                            Text(connectionSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section(L10n.t("Sync", appLanguage)) {
                    if hasPendingSyncWork {
                        LabeledContent(L10n.t("Waiting", appLanguage), value: pendingSummary)
                    }

                    Button {
                        Task {
                            await store.syncNow()
                        }
                    } label: {
                        SyncButtonLabel(state: syncButtonState)
                    }
                    .disabled(!store.isAuthenticated || store.isSyncing)
                    .accessibilityLabel(syncButtonState.accessibilityLabel)

                    NavigationLink(L10n.t("Advanced Sync", appLanguage)) {
                        AdvancedSyncSettingsView()
                    }
                    .disabled(!store.isAuthenticated)
                }

                Section(L10n.t("Storage & Diagnostics", appLanguage)) {
                    StorageSummaryLink()
                }

                Section(L10n.t("Organization", appLanguage)) {
                    NavigationLink(L10n.t("Tags", appLanguage)) {
                        TagManagementView()
                    }
                }

                Section(L10n.t("Appearance", appLanguage)) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Button {
                            store.setAppAppearanceMode(mode)
                        } label: {
                            AppearanceModeRow(
                                mode: mode,
                                isSelected: store.appAppearanceMode == mode
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.appAppearanceMode == mode ? .isSelected : [])
                    }
                }

                Section(L10n.t("Language", appLanguage)) {
                    ForEach(AppLanguageMode.allCases) { mode in
                        Button {
                            store.setAppLanguageMode(mode)
                        } label: {
                            LanguageModeRow(
                                mode: mode,
                                isSelected: store.appLanguageMode == mode
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.appLanguageMode == mode ? .isSelected : [])
                    }
                }

                Section(L10n.t("AI Language", appLanguage)) {
                    ForEach(AILanguageMode.allCases) { mode in
                        Button {
                            store.setAILanguageMode(mode)
                        } label: {
                            AILanguageModeRow(
                                mode: mode,
                                isSelected: store.aiLanguageMode == mode
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.aiLanguageMode == mode ? .isSelected : [])
                    }
                }

                Section(L10n.t("Feature Modules", appLanguage)) {
                    Toggle(
                        L10n.t("Show Tags in Timeline", appLanguage),
                        isOn: Binding(
                            get: { store.showTagsInTimeline },
                            set: { store.setShowTagsInTimeline($0) }
                        )
                    )

                    Toggle(
                        L10n.t("AI Title Auto-Insert", appLanguage),
                        isOn: Binding(
                            get: { store.aiTitleAutoInsertEnabled },
                            set: { store.setAITitleAutoInsertEnabled($0) }
                        )
                    )
                }
            }
            .navigationTitle(L10n.t("Settings", appLanguage))
            .alert(L10n.t("Error", appLanguage), isPresented: errorBinding) {
                Button(L10n.t("OK", appLanguage), role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.clearError() }
        )
    }

    private var connectionSummary: String {
        if store.isAuthenticated {
            return "\(L10n.t("Linked to", appLanguage)) \(serverHost)"
        }

        return L10n.t("Not logged in", appLanguage)
    }

    private var serverHost: String {
        URL(string: store.serverURLString)?.host ?? store.serverURLString
    }

    private var pendingSummary: String {
        let changes = store.pendingOperationCount
        let uploads = store.pendingUploadCount

        if changes == 0 && uploads == 0 {
            return L10n.t("None", appLanguage)
        }

        if uploads == 0 {
            return "\(changes) \(L10n.t(changes == 1 ? "change" : "changes", appLanguage))"
        }

        if changes == 0 {
            return "\(uploads) \(L10n.t(uploads == 1 ? "upload" : "uploads", appLanguage))"
        }

        return "\(changes) \(L10n.t(changes == 1 ? "change" : "changes", appLanguage)), \(uploads) \(L10n.t(uploads == 1 ? "upload" : "uploads", appLanguage))"
    }

    private var hasPendingSyncWork: Bool {
        store.pendingOperationCount > 0 || store.pendingUploadCount > 0
    }

    private var syncButtonState: SyncButtonState {
        if !store.isAuthenticated {
            return .notLoggedIn
        }

        if store.isSyncing {
            return .syncing
        }

        if hasPendingSyncWork {
            return .needsSync
        }

        return .synced
    }
}

private struct AppearanceModeRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let mode: AppAppearanceMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.systemImageName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(L10n.t(mode.title, appLanguage))
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct LanguageModeRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let mode: AppLanguageMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode.systemImageName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(mode.title(language: appLanguage))
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private struct AILanguageModeRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let mode: AILanguageMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode == .auto ? "wand.and.stars" : "textformat")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title(language: appLanguage))
                    .foregroundStyle(.primary)
                Text(mode.subtitle(language: appLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

private extension AppAppearanceMode {
    var systemImageName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}

private struct SyncButtonLabel: View {
    @Environment(\.appLanguage) private var appLanguage

    let state: SyncButtonState

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if state == .syncing {
                    SpinningSyncIcon()
                } else {
                    Image(systemName: state.systemImageName)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            Text(state.title(language: appLanguage))
        }
        .foregroundStyle(state.tint)
    }
}

private enum SyncButtonState {
    case notLoggedIn
    case needsSync
    case syncing
    case synced

    func title(language: AppResolvedLanguage) -> String {
        switch self {
        case .notLoggedIn:
            return L10n.t("Log In First", language)
        case .needsSync:
            return L10n.t("Sync Now", language)
        case .syncing:
            return L10n.t("Syncing", language)
        case .synced:
            return L10n.t("Synced", language)
        }
    }

    var systemImageName: String {
        switch self {
        case .notLoggedIn:
            return "lock"
        case .needsSync, .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .synced:
            return .green
        case .notLoggedIn:
            return .secondary
        case .needsSync, .syncing:
            return .accentColor
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .notLoggedIn:
            return "Log in before syncing"
        case .needsSync:
            return "Sync now"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced. Tap to check again."
        }
    }
}

private struct SpinningSyncIcon: View {
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

private struct ServerDeviceSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var serverURLString = AppSettings.serverURLString
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoggingIn = false

    var body: some View {
        Form {
            Section(L10n.t("Server", appLanguage)) {
                TextField(L10n.t("Server URL", appLanguage), text: $serverURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                Button(L10n.t("Save Server", appLanguage)) {
                    store.updateServerURL(serverURLString)
                    serverURLString = store.serverURLString
                }
                .disabled(serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverURLString == store.serverURLString)
            }

            if store.isAuthenticated {
                Section(L10n.t("Device", appLanguage)) {
                    LabeledContent(L10n.t("Status", appLanguage), value: L10n.t("Linked", appLanguage))

                    if let deviceId = store.deviceId {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("Device ID", appLanguage))
                            Text(deviceId)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.logout()
                    } label: {
                        Text(L10n.t("Log Out", appLanguage))
                    }
                }
            } else {
                Section(L10n.t("Login", appLanguage)) {
                    HStack {
                        Group {
                            if isPasswordVisible {
                                TextField(L10n.t("Password", appLanguage), text: $password)
                            } else {
                                SecureField(L10n.t("Password", appLanguage), text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        guard !isLoggingIn else {
                            return
                        }

                        isLoggingIn = true
                        store.clearError()
                        Task {
                            let didLogin = await store.login(serverURLString: serverURLString, password: password)
                            serverURLString = store.serverURLString

                            if didLogin {
                                password = ""
                            }

                            isLoggingIn = false
                        }
                    } label: {
                        LoginButtonLabel(isLoggingIn: isLoggingIn)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!canLogIn)
                    .animation(.easeOut(duration: 0.16), value: isLoggingIn)
                }
            }
        }
        .navigationTitle(L10n.t("Server & Device", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            serverURLString = store.serverURLString
        }
    }

    private var canLogIn: Bool {
        !isLoggingIn
            && !serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }
}

private struct LoginButtonLabel: View {
    @Environment(\.appLanguage) private var appLanguage

    let isLoggingIn: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isLoggingIn {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
            } else {
                Image(systemName: "key.fill")
                    .font(.body.weight(.semibold))
            }

            Text(L10n.t(isLoggingIn ? "Logging In" : "Log In", appLanguage))
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.28))
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AdvancedSyncSettingsView: View {
    @EnvironmentObject private var store: TimelineStore
    @Environment(\.appLanguage) private var appLanguage
    @State private var operationCounts: [OutboxOperationTypeCount] = []

    var body: some View {
        Form {
            Section {
                Button {
                    Task {
                        await store.resyncFromServer()
                    }
                } label: {
                    Text(L10n.t(store.isSyncing ? "Rebuilding" : "Rebuild From Server", appLanguage))
                }
                .disabled(!store.isAuthenticated || store.isSyncing)
            } footer: {
                Text(L10n.t("Use this only when this iPhone looks out of date. Normal sync is enough for daily use.", appLanguage))
            }

            Section {
                if operationCounts.isEmpty {
                    Text(L10n.t("No pending operations", appLanguage))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(operationCounts) { item in
                        LabeledContent("\(item.type) · \(item.status)", value: "\(item.count)")
                    }
                }
            } header: {
                Text(L10n.t("Outbox", appLanguage))
            } footer: {
                Text(L10n.t("Operation counts do not include private text bodies.", appLanguage))
            }
        }
        .navigationTitle(L10n.t("Advanced Sync", appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            operationCounts = store.pendingOperationTypeCounts()
        }
    }
}

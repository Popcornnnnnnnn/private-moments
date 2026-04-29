import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TimelineStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    NavigationLink {
                        ServerDeviceSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server & Device")
                            Text(connectionSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section("Sync") {
                    if hasPendingSyncWork {
                        LabeledContent("Waiting", value: pendingSummary)
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

                    NavigationLink("Advanced Sync") {
                        AdvancedSyncSettingsView()
                    }
                    .disabled(!store.isAuthenticated)
                }

                Section("Storage") {
                    StorageSummaryLink()
                }
            }
            .navigationTitle("Settings")
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
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
            return "Linked to \(serverHost)"
        }

        return "Not logged in"
    }

    private var serverHost: String {
        URL(string: store.serverURLString)?.host ?? store.serverURLString
    }

    private var pendingSummary: String {
        let changes = store.pendingOperationCount
        let uploads = store.pendingUploadCount

        if changes == 0 && uploads == 0 {
            return "None"
        }

        if uploads == 0 {
            return "\(changes) changes"
        }

        if changes == 0 {
            return "\(uploads) uploads"
        }

        return "\(changes) changes, \(uploads) uploads"
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

private struct SyncButtonLabel: View {
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

            Text(state.title)
        }
        .foregroundStyle(state.tint)
    }
}

private enum SyncButtonState {
    case notLoggedIn
    case needsSync
    case syncing
    case synced

    var title: String {
        switch self {
        case .notLoggedIn:
            return "Log In First"
        case .needsSync:
            return "Sync Now"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
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
    @State private var serverURLString = AppSettings.serverURLString
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoggingIn = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $serverURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                Button("Save Server") {
                    store.updateServerURL(serverURLString)
                    serverURLString = store.serverURLString
                }
                .disabled(serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || serverURLString == store.serverURLString)
            }

            if store.isAuthenticated {
                Section("Device") {
                    LabeledContent("Status", value: "Linked")

                    if let deviceId = store.deviceId {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Device ID")
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
                        Text("Log Out")
                    }
                }
            } else {
                Section("Login") {
                    HStack {
                        Group {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
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
        .navigationTitle("Server & Device")
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

            Text(isLoggingIn ? "Logging In" : "Log In")
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

    var body: some View {
        Form {
            Section {
                Button {
                    Task {
                        await store.resyncFromServer()
                    }
                } label: {
                    Text(store.isSyncing ? "Rebuilding" : "Rebuild From Server")
                }
                .disabled(!store.isAuthenticated || store.isSyncing)
            } footer: {
                Text("Use this only when this iPhone looks out of date. Normal sync is enough for daily use.")
            }
        }
        .navigationTitle("Advanced Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}

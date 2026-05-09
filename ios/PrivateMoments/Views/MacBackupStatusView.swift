import SwiftUI

struct MacBackupStatusView: View {
    let diagnostics: MacOperationsDiagnostics

    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        repositorySection
        latestBackupSection
        snapshotsSection
        recoverySection
    }

    private var repositorySection: some View {
        Section(L10n.t("Repository", appLanguage)) {
            if let repository = diagnostics.repository {
                LabeledContent(
                    L10n.t("Status", appLanguage),
                    value: L10n.t(repository.configured ? "Configured" : "Not configured", appLanguage)
                )
                LabeledContent(
                    L10n.t("Initialized", appLanguage),
                    value: L10n.t(repository.initialized ? "Yes" : "No", appLanguage)
                )
                LabeledContent(
                    L10n.t("Restic", appLanguage),
                    value: repository.resticAvailable ? (repository.resticVersion ?? L10n.t("Available", appLanguage)) : L10n.t("Unavailable", appLanguage)
                )

                if repository.schedule.enabled {
                    LabeledContent(L10n.t("Schedule", appLanguage), value: repository.schedule.timeOfDay)
                    if let nextRunAt = repository.schedule.nextRunAt {
                        LabeledContent(L10n.t("Next backup", appLanguage), value: shortTimestamp(nextRunAt))
                    }
                } else {
                    LabeledContent(L10n.t("Schedule", appLanguage), value: L10n.t("Off", appLanguage))
                }
            } else {
                LabeledContent(L10n.t("Status", appLanguage), value: L10n.t("Unavailable", appLanguage))
            }
        }
    }

    private var latestBackupSection: some View {
        Section(L10n.t("Latest backup job", appLanguage)) {
            if let runningJob = diagnostics.runningJob, runningJob.type.hasPrefix("backup_") {
                jobRows(runningJob)
            } else if let latestJob = diagnostics.latestBackupJob {
                jobRows(latestJob)
            } else {
                Text(L10n.t("No backup job yet", appLanguage))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var snapshotsSection: some View {
        Section(L10n.t("Latest snapshot", appLanguage)) {
            if let latestSnapshot = diagnostics.latestSnapshot {
                LabeledContent(L10n.t("Snapshot", appLanguage), value: latestSnapshot.shortId)
                LabeledContent(L10n.t("Created", appLanguage), value: shortTimestamp(latestSnapshot.time))

                if let hostname = latestSnapshot.hostname, !hostname.isEmpty {
                    LabeledContent(L10n.t("Host", appLanguage), value: hostname)
                }

                if !latestSnapshot.paths.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Paths", appLanguage))
                            .font(.subheadline)
                        Text(latestSnapshot.paths.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text(L10n.t("No snapshot yet", appLanguage))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recoverySection: some View {
        Section {
            if let repository = diagnostics.repository {
                if let repositoryPath = repository.repositoryPath, !repositoryPath.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Repository path", appLanguage))
                            .font(.subheadline)
                        Text(repositoryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let keyFilePath = repository.keyFilePath, !keyFilePath.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Key file", appLanguage))
                            .font(.subheadline)
                        Text(keyFilePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Text(L10n.t("Backup actions stay in Mac Admin.", appLanguage))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text(L10n.t("Recovery files", appLanguage))
        }
    }

    @ViewBuilder
    private func jobRows(_ job: AdminMaintenanceJob) -> some View {
        LabeledContent(L10n.t("Type", appLanguage), value: maintenanceJobTitle(job.type))
        LabeledContent(L10n.t("Status", appLanguage), value: L10n.t(job.status.capitalized, appLanguage))

        if job.status == "running" {
            LabeledContent(L10n.t("Progress", appLanguage), value: "\(job.progress)%")
        }

        if let startedAt = job.startedAt {
            LabeledContent(L10n.t("Started", appLanguage), value: shortTimestamp(startedAt))
        }

        if let finishedAt = job.finishedAt {
            LabeledContent(L10n.t("Finished", appLanguage), value: shortTimestamp(finishedAt))
        } else {
            LabeledContent(L10n.t("Created", appLanguage), value: shortTimestamp(job.createdAt))
        }

        if let errorCode = job.errorCode, !errorCode.isEmpty {
            LabeledContent(L10n.t("Error", appLanguage), value: errorCode)
        }

        if let errorMessage = job.errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func maintenanceJobTitle(_ value: String) -> String {
        switch value {
        case "backup_create":
            return L10n.t("Backup", appLanguage)
        case "backup_check":
            return L10n.t("Backup check", appLanguage)
        case "backup_restore":
            return L10n.t("Restore", appLanguage)
        case "backup_promote":
            return L10n.t("Promote", appLanguage)
        default:
            return value.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func shortTimestamp(_ value: String) -> String {
        value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }
}

//
//  UserDataBackupView.swift
//  SneakPeak
//
//  Export/import of all user data as JSON (G7). Not offered on tvOS, which
//  has no document picker.
//

import SwiftUI
import UniformTypeIdentifiers

#if !os(tvOS)
struct UserDataBackupView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showingImportConfirmation = false
    @State private var pendingImportURL: URL?

    private var toastManager: ToastManager? { appEnvironment?.toastManager }

    private var backupService: UserDataBackupService? {
        guard let appEnvironment else { return nil }
        return UserDataBackupService(
            dataManager: appEnvironment.dataManager,
            mediaSourcesManager: appEnvironment.mediaSourcesManager
        )
    }

    static let backupUTType = UTType(filenameExtension: "sneakpeak-backup", conformingTo: .json)
        ?? UTType.json

    var body: some View {
        SettingsFormContainer {
            SettingsFormSection("settings.backup.sectionTitle", footer: "settings.backup.footer") {
                Button {
                    exportBackup()
                } label: {
                    Label(String(localized: "settings.backup.export"), systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)

                Button {
                    isImporting = true
                } label: {
                    Label(String(localized: "settings.backup.import"), systemImage: "square.and.arrow.down")
                }

                if isExporting {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "settings.backup.exporting"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.backup.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileExporter(
            isPresented: $isExporting,
            document: exportURL.map { BackupDocument(url: $0) },
            contentType: Self.backupUTType,
            defaultFilename: "SneakPeak-backup-\(Self.dateStamp())"
        ) { result in
            if case .failure(let error) = result {
                toastManager?.showError(
                    String(localized: "settings.backup.export.error"),
                    subtitle: error.localizedDescription
                )
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [Self.backupUTType, .json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                pendingImportURL = urls.first
                showingImportConfirmation = true
            }
        }
        .confirmationDialog(
            String(localized: "settings.backup.import.confirmation"),
            isPresented: $showingImportConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.backup.import"), role: .destructive) {
                importBackup()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.backup.import.message"))
        }
    }

    // MARK: - Actions

    private func exportBackup() {
        guard let backupService else { return }
        Task {
            do {
                let data = try backupService.exportData()
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SneakPeak-backup-\(Self.dateStamp()).json")
                try data.write(to: url, options: .atomic)
                exportURL = url
                // Present the exporter only once the file exists — presenting
                // earlier would show a dialog with no document.
                isExporting = true
            } catch {
                toastManager?.showError(
                    String(localized: "settings.backup.export.error"),
                    subtitle: error.localizedDescription
                )
            }
        }
    }

    private func importBackup() {
        guard let backupService, let url = pendingImportURL else { return }
        Task {
            do {
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let summary = try backupService.importData(data)
                toastManager?.showSuccess(
                    String(localized: "settings.backup.import.success"),
                    subtitle: String(
                        format: String(localized: "settings.backup.import.summary %lld %lld %lld %lld"),
                        summary.subscriptions,
                        summary.watchEntries,
                        summary.bookmarks,
                        summary.playlists
                    )
                )
            } catch {
                toastManager?.showError(
                    String(localized: "settings.backup.import.error"),
                    subtitle: error.localizedDescription
                )
            }
            pendingImportURL = nil
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

/// `fileExporter` wrapper around a written temp file.
private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UserDataBackupView.backupUTType] }

    let url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(contentsOf: url, options: .immediate)
    }
}
#endif

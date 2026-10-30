// Settings › Backup (Phase 6 S2, PHASE6_PLAN decision 5).
//
//   Export Backup           ShareLink of a `.tabulabackup` written from the in-memory snapshot when the page appears
//   Restore from Backup…    fileImporter → BackupImport (verified, nothing changed on failure) → confirmation dialog:
//                           Merge (default) / Replace… → destructive alert naming what is replaced and where the
//                           automatic pre-restore copy is kept → copy written to `<store>/Backups` FIRST, then applied
//   Automatic copies        the archives in `<store>/Backups` (pre-restore, pre-migration), each shareable
//
// HIG: file management (system share sheet + document picker), alerts (destructive button + Cancel, plain-word errors
// that say nothing was changed), settings (one pushed page). No UTType is declared: the file is shared and picked as
// plain data and validated on import (`.data` picker), so a wrong file gets "This file isn't a Tabula backup".
// Attachment files are not in a backup (BackupArchive format 1): the footer says so (RISKS #56).
// APIs: ShareLink(item:label:) (URL is Transferable, iOS 16), View.fileImporter(isPresented:allowedContentTypes:
//       onCompletion:) (security-scoped URL, ENVIRONMENT §22), View.confirmationDialog(_:isPresented:titleVisibility:
//       presenting:actions:message:), View.alert(_:isPresented:presenting:actions:message:), UTType.data.
import SwiftUI
import TimetableCore
import TimetableUI
import UniformTypeIdentifiers

struct SettingsBackupView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var exportFailed = false
    @State private var automatic: [BackupFolder.Entry] = []
    @State private var importing = false
    @State private var picked: PickedBackup?
    @State private var confirmingReplace: PickedBackup?
    @State private var result: RestoreResult?

    var body: some View {
        Form {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label { Text("settings.backup.export") } icon: { Image(systemName: "square.and.arrow.up") }
                    }
                } else {
                    LabeledContent {
                        if !exportFailed { ProgressView() }
                    } label: {
                        Label { Text("settings.backup.export") } icon: { Image(systemName: "square.and.arrow.up") }
                    }
                    .foregroundStyle(.secondary)
                }
                Button { importing = true } label: {
                    Label { Text("settings.backup.restore") } icon: { Image(systemName: "arrow.down.doc") }
                }
                .disabled(model.isReadOnly || model.database == nil)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if exportFailed { Text("settings.backup.export.failed") }
                    Text("settings.backup.footer")
                }
            }
            if !automatic.isEmpty {
                Section {
                    ForEach(automatic) { entry in
                        ShareLink(item: entry.url) {
                            Label {
                                Text(verbatim: date(entry.createdAt, .abbreviated))
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                    }
                } header: {
                    Text("settings.backup.automatic.header")
                } footer: {
                    Text("settings.backup.automatic.footer")
                }
            }
        }
        .navigationTitle(Text("settings.backup.title"))
        .task { await prepareExport() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { pick($0) }
        .confirmationDialog(Text("settings.backup.mode.title"), isPresented: isPresented($picked),
                            titleVisibility: .visible, presenting: picked) { backup in
            Button("settings.backup.mode.merge") { restore(backup, mode: .merge) }
            Button("settings.backup.mode.replace", role: .destructive) { confirmingReplace = backup }
            Button("editor.common.cancel", role: .cancel) {}
        } message: { backup in
            Text(verbatim: model.renderer.format(key: "settings.backup.mode.message", arguments: [.text(date(backup.createdAt))]))
        }
        .alert(Text("settings.backup.replace.title"), isPresented: isPresented($confirmingReplace),
               presenting: confirmingReplace) { backup in
            Button("settings.backup.replace.confirm", role: .destructive) { restore(backup, mode: .replace) }
            Button("editor.common.cancel", role: .cancel) {}
        } message: { backup in
            Text(verbatim: model.renderer.format(key: "settings.backup.replace.message", arguments: [.text(date(backup.createdAt))]))
        }
        .alert(result?.titleKey ?? "", isPresented: isPresented($result), presenting: result) { _ in
            Button("editor.warnings.ok") {}
        } message: { result in
            Text(result.messageKey)
        }
    }

    // MARK: Export

    private func prepareExport() async {
        automatic = BackupFolder.entries(in: model.environment.backupDirectory)
        guard let database = model.database else { exportFailed = true; return }
        let day = model.today
        let name = String(format: "Tabula %04d-%02d-%02d.%@", day.year, day.month, day.day, BackupFolder.fileExtension)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try BackupArchive.make(from: database, createdAt: model.now).encoded().write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportFailed = true
        }
    }

    // MARK: Restore

    private func pick(_ selection: Result<URL, Error>) {
        guard case .success(let url) = selection else {
            result = .problem("settings.backup.error.unreadable")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do throws(BackupImportProblem) {
            let (manifest, database) = try BackupImport.read(contentsOf: url)
            picked = PickedBackup(createdAt: manifest.createdAt, database: database)
        } catch {
            result = .problem(LocalizedStringKey(error.messageKey))
        }
    }

    private func restore(_ backup: PickedBackup, mode: BackupRestore.Mode) {
        if mode == .replace {
            // The automatic copy is written before anything changes; no copy → no replace.
            guard let current = model.database,
                  (try? BackupFolder.write(.make(from: current, createdAt: model.now), label: "pre-restore",
                                           in: model.environment.backupDirectory)) != nil else {
                result = .problem("settings.backup.error.copyFailed")
                return
            }
            automatic = BackupFolder.entries(in: model.environment.backupDirectory)
        }
        switch model.apply(.restore(backup.database, mode: mode)) {
        case .applied:
            result = RestoreResult(titleKey: "settings.backup.done.title",
                                   messageKey: mode == .merge ? "settings.backup.done.merged" : "settings.backup.done.replaced")
            Task { await model.flush() }
        case .rejected, .readOnly, .failed:
            result = .problem("settings.backup.error.apply")
        }
    }

    private func date(_ value: Date, _ style: Date.FormatStyle.DateStyle = .long) -> String {
        value.formatted(Date.FormatStyle(date: style, time: .shortened, locale: model.formatter.locale,
                                         timeZone: model.calendarContext.timeZone))
    }

    private func isPresented<Value>(_ binding: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}

/// A verified backup waiting for the user's choice.
private struct PickedBackup {
    let createdAt: Date
    let database: TabulaDatabase
}

/// The alert after a restore attempt.
private struct RestoreResult {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey

    static func problem(_ messageKey: LocalizedStringKey) -> RestoreResult {
        RestoreResult(titleKey: "settings.backup.error.title", messageKey: messageKey)
    }
}

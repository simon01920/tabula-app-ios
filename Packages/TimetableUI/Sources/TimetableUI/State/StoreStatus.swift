// What the persistence layer reports, turned into app state the UI can show (recovery / read-only banner,
// blocking error screen). Pure mapping from TimetableCore's `LoadReport` / `RepositoryError`; Linux-tested.
// The UI owns the text: every case has catalog keys (`store.*`).
import Foundation
import TimetableCore

/// A banner above the app shell. Never blocks the UI.
public enum StoreBanner: Equatable, Sendable {
    /// The database was missing or corrupt and the last good backup was loaded (recent changes may be lost).
    case restoredFromBackup
    /// An interrupted save was discarded on launch (that change is lost).
    case discardedIncompleteWrite
    /// The data was written by a newer app version: shown, but every change is refused until the app updates.
    case readOnly(fileSchemaVersion: Int)
    /// The last save failed; changes are kept in memory and saving is retried with the next change.
    case saveFailed
    /// A change was refused because it would make the data invalid (nothing was changed).
    case changeRejected

    /// Catalog key of the banner title.
    public var titleKey: String {
        switch self {
        case .restoredFromBackup: return "store.banner.restored.title"
        case .discardedIncompleteWrite: return "store.banner.discardedWrite.title"
        case .readOnly: return "store.banner.readOnly.title"
        case .saveFailed: return "store.banner.saveFailed.title"
        case .changeRejected: return "store.banner.changeRejected.title"
        }
    }

    /// Catalog key of the explanation.
    public var messageKey: String {
        switch self {
        case .restoredFromBackup: return "store.banner.restored.message"
        case .discardedIncompleteWrite: return "store.banner.discardedWrite.message"
        case .readOnly: return "store.banner.readOnly.message"
        case .saveFailed: return "store.banner.saveFailed.message"
        case .changeRejected: return "store.banner.changeRejected.message"
        }
    }

    /// SF Symbol shown with the text (status is never colour-only).
    public var symbolName: String {
        switch self {
        case .restoredFromBackup, .discardedIncompleteWrite: return "arrow.counterclockwise.circle"
        case .readOnly: return "lock.circle"
        case .saveFailed, .changeRejected: return "exclamationmark.triangle"
        }
    }

    /// `true` when the user may dismiss it (read-only stays until the app is updated).
    public var isDismissible: Bool {
        if case .readOnly = self { return false }
        return true
    }
}

/// A load failure that leaves nothing to show. The app must not offer onboarding here: onboarding would save over
/// files that may still be recoverable (or that a newer app version can read).
public enum StoreProblem: Equatable, Sendable {
    /// Neither the database nor its backup can be read. The files are kept untouched for support.
    case unrecoverable
    /// Written by a newer app version this version cannot read at all.
    case newerVersion(fileSchemaVersion: Int)
    /// Any other failure (I/O, permissions).
    case other(String)

    /// Catalog key of the title.
    public var titleKey: String {
        switch self {
        case .unrecoverable: return "store.problem.unrecoverable.title"
        case .newerVersion: return "store.problem.newerVersion.title"
        case .other: return "store.problem.other.title"
        }
    }

    /// Catalog key of the explanation.
    public var messageKey: String {
        switch self {
        case .unrecoverable: return "store.problem.unrecoverable.message"
        case .newerVersion: return "store.problem.newerVersion.message"
        case .other: return "store.problem.other.message"
        }
    }
}

/// Result of loading the store at launch.
public enum StoreLoadOutcome: Equatable, Sendable {
    /// Data loaded; `banners` lists what to tell the user (in order); `isReadOnly` blocks every change.
    case loaded(TabulaDatabase, banners: [StoreBanner], isReadOnly: Bool)
    /// Nothing stored yet: first launch → onboarding.
    case empty
    /// Nothing can be shown.
    case failed(StoreProblem)

    /// Maps a successful load and its report (`nil` for repositories without reports, e.g. in-memory).
    public static func loaded(_ database: TabulaDatabase, report: LoadReport?) -> StoreLoadOutcome {
        guard let report else { return .loaded(database, banners: [], isReadOnly: false) }
        var banners: [StoreBanner] = []
        for event in report.events {
            let banner: StoreBanner
            switch event {
            case .restoredFromBackup: banner = .restoredFromBackup
            case .discardedIncompleteWrite: banner = .discardedIncompleteWrite
            case .quarantinedCorruptFile: continue   // detail of the restore; one banner is enough
            }
            if !banners.contains(banner) { banners.append(banner) }
        }
        // Restoring already explains lost changes; the discarded write is then not worth a second banner.
        if banners.contains(.restoredFromBackup) { banners.removeAll { $0 == .discardedIncompleteWrite } }
        if report.isReadOnly { banners.insert(.readOnly(fileSchemaVersion: report.fileSchemaVersion), at: 0) }
        return .loaded(database, banners: banners, isReadOnly: report.isReadOnly)
    }

    /// Maps a load error.
    public static func failed(_ error: any Error) -> StoreLoadOutcome {
        guard let error = error as? RepositoryError else { return .failed(.other(String(describing: error))) }
        switch error {
        case .notFound: return .empty
        case .unrecoverable: return .failed(.unrecoverable)
        case .newerSchemaUnreadable(let version, _), .readOnly(let version): return .failed(.newerVersion(fileSchemaVersion: version))
        case .unsupportedSchemaVersion, .writeFailed: return .failed(.other(String(describing: error)))
        }
    }
}

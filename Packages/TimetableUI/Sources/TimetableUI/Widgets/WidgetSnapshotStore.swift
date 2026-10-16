// Where the widget snapshot lives in the App Group container and how it is (de)serialised. Shared by the app's writer
// and the extension's reader so both agree on the path and the format. Foundation only, Linux-tested on temp dirs.
//
//   <App Group container>/Widgets/widget-snapshot.json      (separate from the store folder `Tabula/`)
//
// Writes are atomic (`Data.WritingOptions.atomic`: write to a temporary file, then rename), so the extension never
// reads half a file. Reads never throw: a missing, unreadable, corrupt or newer-version file is `nil`, which the
// widget shows as "Open Tabula" (never stale or invented data).
import Foundation

public enum WidgetSnapshotStore {
    /// Folder inside the App Group container.
    public static let folderName = "Widgets"
    /// File name.
    public static let fileName = "widget-snapshot.json"
    /// Refuse files larger than this (a valid snapshot is far smaller; protects the extension's memory budget).
    public static let maxFileBytes = 512 * 1024

    /// The snapshot file in `container` (the App Group container URL).
    public static func fileURL(container: URL) -> URL {
        container.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)
    }

    /// The encoded snapshot (stable key order, so unchanged content gives identical bytes).
    public static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// The snapshot in `data`, or `nil` when it is not a snapshot this version can read.
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        guard data.count <= maxFileBytes,
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              (1...WidgetSnapshot.currentVersion).contains(snapshot.version) else { return nil }
        return snapshot
    }

    /// Writes `data` atomically to the snapshot file in `container`, creating the folder.
    public static func write(_ data: Data, container: URL) throws {
        let url = fileURL(container: container)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    /// Reads the snapshot from `container`, or `nil` (see the header).
    public static func read(container: URL) -> WidgetSnapshot? {
        let url = fileURL(container: container)
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
           size.intValue > maxFileBytes {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}

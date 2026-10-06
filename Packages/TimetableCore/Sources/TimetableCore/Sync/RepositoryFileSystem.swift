import Foundation

/// The file operations `FileRepository` needs — a seam so tests can simulate crashes between steps.
public protocol RepositoryFileSystem: Sendable {
    /// The file's contents, or `nil` when it does not exist.
    func contents(of url: URL) throws -> Data?
    /// Creates or truncates the file, writes `data` and flushes it to storage (`fsync`).
    func write(_ data: Data, to url: URL) throws
    /// Atomically renames `source` onto `destination`, replacing `destination` if it exists (`rename(2)`;
    /// both must be in the same directory/volume).
    func replaceItem(at destination: URL, withItemAt source: URL) throws
    /// Deletes the file; no error when it does not exist.
    func removeItem(at url: URL) throws
    /// `true` when a file exists at `url`.
    func fileExists(at url: URL) -> Bool
    /// Creates the directory (and intermediate directories) if needed.
    func createDirectory(at url: URL) throws
}

extension RepositoryFileSystem {
    /// Copies `source` to `destination` (durably); no-op when `source` does not exist.
    func copyItem(at source: URL, to destination: URL) throws {
        if let data = try contents(of: source) { try write(data, to: destination) }
    }
}

/// Errors of `FoundationFileSystem`.
public enum RepositoryFileSystemError: Error, Hashable, Sendable {
    /// The file could not be created.
    case createFailed(path: String)
    /// `rename(2)` failed with `errno`.
    case renameFailed(path: String, errno: Int32)
}

/// The production file system (Foundation; POSIX `rename` for the atomic replace).
public struct FoundationFileSystem: RepositoryFileSystem {
    /// Creates the file system.
    public init() {}

    public func contents(of url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw RepositoryFileSystemError.createFailed(path: url.path)
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    public func replaceItem(at destination: URL, withItemAt source: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw RepositoryFileSystemError.renameFailed(path: destination.path, errno: errno)
        }
    }

    public func removeItem(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

import Foundation

/// Persists the encrypted `BackupEnvelope` as a single JSON document in the
/// app's iCloud Drive ubiquity container. Files in the container are also
/// cached locally, so unlock works offline once the backup has synced down.
public struct ICloudBackupStore: Sendable {
    public static let fileName = "wallet-backup.v1.json"

    private let containerIdentifier: String?
    private var fileManager: FileManager { FileManager.default }

    /// - Parameter containerIdentifier: pass nil for the app's first
    ///   ubiquity container from entitlements.
    public init(containerIdentifier: String? = nil) {
        self.containerIdentifier = containerIdentifier
    }

    /// True when the ubiquity container is reachable (device signed into
    /// iCloud with iCloud Drive on). When false, the store transparently
    /// falls back to app-local storage so create/restore still work — the
    /// UI must surface that the wallet is *not* protected against device
    /// loss until iCloud comes back.
    public var isUsingICloud: Bool {
        fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) != nil
    }

    private func backupURL() throws -> URL {
        let directory: URL
        if let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) {
            directory = container.appendingPathComponent("Documents", isDirectory: true)
        } else {
            // No iCloud (simulator without sign-in, iCloud Drive disabled).
            directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WalletBackupLocal", isDirectory: true)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(Self.fileName)
    }

    public func backupExists() -> Bool {
        guard let url = try? backupURL() else { return false }
        if fileManager.fileExists(atPath: url.path) { return true }
        // The item may exist in iCloud but not be materialized locally yet.
        return (try? url.checkResourceIsReachable()) ?? false
            || fileManager.isUbiquitousItem(at: url)
    }

    public func load() async throws -> BackupEnvelope {
        let url = try backupURL()

        if !fileManager.fileExists(atPath: url.path), fileManager.isUbiquitousItem(at: url) {
            // Ask iCloud to materialize the file, then poll briefly.
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            for _ in 0..<40 where !fileManager.fileExists(atPath: url.path) {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        guard fileManager.fileExists(atPath: url.path) else {
            throw WalletKitError.backupNotFound
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw WalletKitError.backupCorrupted("undecodable envelope: \(error.localizedDescription)")
        }
    }

    public func save(_ envelope: BackupEnvelope) throws {
        let url = try backupURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)

        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { dest in
            do {
                try data.write(to: dest, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }
}

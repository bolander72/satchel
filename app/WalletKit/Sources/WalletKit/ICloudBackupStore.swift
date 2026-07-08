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

    private func backupURL() throws -> URL {
        guard let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw WalletKitError.icloudUnavailable
        }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents.appendingPathComponent(Self.fileName)
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

        if !fileManager.fileExists(atPath: url.path) {
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

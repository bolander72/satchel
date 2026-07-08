import Foundation
import WalletKit

/// App-layer state machine. Owns the engine, the decrypted secrets (memory
/// only, per session), and the backup lifecycle. Every entry into the wallet
/// — create, restore/unlock, send — goes through the Face ID gate first.
@MainActor
final class WalletStore: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// No unlocked wallet yet. `hasBackup` decides Create vs Unlock UI.
        case welcome(hasBackup: Bool)
        case working(String)
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var balance = WalletBalance(confirmedSats: 0, pendingSats: 0)
    @Published private(set) var transactions: [WalletTransaction] = []
    @Published private(set) var feeTiers: FeeTiers = .fallback
    @Published private(set) var isSyncing = false
    @Published var lastError: String?
    /// Set when the user taps a payment card in the transcript.
    @Published var incomingRequest: IncomingCard?

    let chain: ChainConfig

    private var engine: WalletEngine?
    private var secrets: WalletSecrets?
    private let keyProvider = SyncedKeychainKeyProvider()
    private let backupStore = ICloudBackupStore()
    private let faceID = FaceIDGate()
    private let feeEstimator = FeeEstimator()
    private var started = false

    init(chain: ChainConfig = .fromBundle()) {
        self.chain = chain
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else {
            if engine != nil { await refresh() }
            return
        }
        started = true
        guard engine == nil else {
            phase = .ready
            return
        }
        phase = .welcome(hasBackup: backupStore.backupExists())
    }

    /// One tap: Face ID → new seed → wallet → encrypted iCloud backup.
    func createWallet() async {
        do {
            try await faceID.authenticate(reason: "Create your Bitcoin wallet")
            phase = .working("Creating your wallet…")

            let secrets = WalletEngine.generateSecrets(network: chain.network)
            let storageDir = Self.walletStorageDirectory()
            let engine = try await Self.offMain {
                try WalletEngine(secrets: secrets, storageDirectory: storageDir)
            }
            self.engine = engine
            self.secrets = secrets

            phase = .working("Backing up to iCloud…")
            try await persistBackup()

            phase = .ready
            await refresh()
        } catch {
            report(error)
            phase = .welcome(hasBackup: backupStore.backupExists())
        }
    }

    /// Face ID → fetch envelope from iCloud → decrypt with the synced
    /// keychain key → rebuild the deterministic wallet → rescan.
    func restoreWallet() async {
        do {
            try await faceID.authenticate(reason: "Unlock your Bitcoin wallet")
            phase = .working("Restoring from iCloud…")

            let envelope = try await backupStore.load()
            guard let keyMaterial = try await keyProvider.existingKeyMaterial() else {
                throw WalletKitError.keyUnavailable(
                    "Backup key hasn't synced to this device yet. Make sure iCloud Keychain is on, then try again."
                )
            }
            let secrets = try BackupCrypto.open(envelope, inputKeyMaterial: keyMaterial)

            let storageDir = Self.walletStorageDirectory()
            let engine = try await Self.offMain {
                try WalletEngine(secrets: secrets, storageDirectory: storageDir)
            }
            self.engine = engine
            self.secrets = secrets

            phase = .ready
            await refresh(fullScan: true)
        } catch {
            report(error)
            phase = .welcome(hasBackup: backupStore.backupExists())
        }
    }

    // MARK: - Chain state

    func refresh(fullScan: Bool = false) async {
        guard let engine, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let esplora = chain.esploraURL
        do {
            try await Self.offMain { try engine.sync(esploraURL: esplora, fullScan: fullScan) }
        } catch {
            // Sync failures are non-fatal: show cached state plus a notice.
            report(error)
        }
        balance = engine.balance()
        transactions = engine.transactions()
        feeTiers = await feeEstimator.tiers(esploraURL: chain.esploraURL, feesURL: chain.feesURL)
    }

    // MARK: - Receive

    func makeReceiveRequest(amountSats: UInt64?, label: String?) async throws -> PaymentRequest {
        guard let engine else { throw WalletKitError.internalError("wallet not ready") }
        let next = try await Self.offMain { try engine.nextReceiveAddress() }
        try? await persistBackup() // advance index hints; best-effort
        return PaymentRequest(address: next.address, amountSats: amountSats, label: label)
    }

    // MARK: - Send

    /// Face ID first, then build + sign. Returns the signed-but-unbroadcast
    /// transaction for the review sheet.
    func prepareSend(to address: String, amountSats: UInt64, feeRateSatPerVb: UInt64) async throws -> SignedSend {
        guard let engine else { throw WalletKitError.internalError("wallet not ready") }
        guard engine.validateAddress(address) else { throw WalletKitError.invalidAddress(address) }
        try await faceID.authenticate(reason: "Approve sending Bitcoin")
        return try await Self.offMain {
            try engine.createSignedTransaction(
                to: address,
                amountSats: amountSats,
                feeRateSatPerVb: feeRateSatPerVb
            )
        }
    }

    func broadcast(_ send: SignedSend) async throws -> String {
        guard let engine else { throw WalletKitError.internalError("wallet not ready") }
        let esplora = chain.esploraURL
        let txid = try await Self.offMain { try engine.broadcast(send, esploraURL: esplora) }
        await refresh()
        return txid
    }

    // MARK: - Backup

    /// Reseals the backup with current index hints. Called after wallet
    /// creation and whenever new addresses are revealed.
    private func persistBackup() async throws {
        guard let engine, var secrets else { return }
        let indexes = engine.revealedIndexes()
        secrets.receiveIndexHint = indexes.receive
        secrets.changeIndexHint = indexes.change
        self.secrets = secrets

        let keyMaterial = try await keyProvider.keyMaterial()
        let envelope = try BackupCrypto.seal(
            secrets,
            inputKeyMaterial: keyMaterial,
            keyProvider: keyProvider.identifier
        )
        try backupStore.save(envelope)
    }

    // MARK: - Helpers

    private func report(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private static func walletStorageDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wallet", isDirectory: true)
    }

    private nonisolated static func offMain<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }
}

extension ChainConfig {
    /// Network is a build setting (`WALLET_NETWORK` → Info.plist `WalletNetwork`):
    /// Debug builds default to signet (Mutinynet) so the team can test with
    /// free coins; Release is mainnet.
    static func fromBundle(_ bundle: Bundle = .main) -> ChainConfig {
        switch bundle.object(forInfoDictionaryKey: "WalletNetwork") as? String {
        case "signet": return .signet
        case "bitcoin": return .mainnet
        default:
            #if DEBUG
                return .signet
            #else
                return .mainnet
            #endif
        }
    }
}

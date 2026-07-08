import Foundation
import LocalAuthentication
import WalletKit

/// Face ID (with device-passcode fallback) in front of every sensitive
/// action. This is UX-level gating in V0 — the cryptographic story is the
/// encrypted backup — and is slated to become passkey-PRF-backed real key
/// derivation later (docs/decisions/0002-encryption-path.md).
struct FaceIDGate {
    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            throw WalletKitError.keyUnavailable(
                availabilityError?.localizedDescription ?? "Face ID and passcode are unavailable on this device."
            )
        }

        let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        guard ok else {
            throw WalletKitError.keyUnavailable("Authentication was not completed.")
        }
    }
}

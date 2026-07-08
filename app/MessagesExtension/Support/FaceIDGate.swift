import Foundation
import LocalAuthentication
import WalletKit

/// Face ID (with device-passcode fallback) in front of every sensitive
/// action. This is UX-level gating in V0 — the cryptographic story is the
/// encrypted backup — and is slated to become passkey-PRF-backed real key
/// derivation later (docs/decisions/0002-encryption-path.md).
struct FaceIDGate {
    func authenticate(reason: String) async throws {
        // A systemCancel means our sheet was preempted — by a presentation
        // transition or another auth UI still tearing down. Those windows
        // can outlast a single retry, so back off and try a few times
        // before surfacing an error.
        var attemptsLeft = 3
        while true {
            do {
                try await evaluateOnce(reason: reason)
                return
            } catch let error as LAError where error.code == .systemCancel && attemptsLeft > 0 {
                attemptsLeft -= 1
                try await Task.sleep(nanoseconds: 900_000_000)
            } catch let error as LAError {
                throw WalletKitError.keyUnavailable(friendlyMessage(for: error))
            }
        }
    }

    private func evaluateOnce(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            throw WalletKitError.keyUnavailable(
                availabilityError.map { friendlyMessage(for: LAError(_nsError: $0)) }
                    ?? "Face ID and passcode are unavailable on this device."
            )
        }

        let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        guard ok else {
            throw WalletKitError.keyUnavailable("Authentication was not completed.")
        }
    }

    private func friendlyMessage(for error: LAError) -> String {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Authentication was canceled. Please try again."
        case .biometryNotEnrolled:
            return "Face ID isn't set up on this device. Set it up in Settings, or make sure a passcode is set."
        case .passcodeNotSet:
            return "This device has no passcode. Set a passcode to protect your wallet."
        case .biometryLockout:
            return "Face ID is locked after too many attempts. Enter your passcode to re-enable it."
        default:
            return error.localizedDescription
        }
    }
}

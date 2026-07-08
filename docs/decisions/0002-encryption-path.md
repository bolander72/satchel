# ADR 0002: Synced-keychain key for V0; passkey PRF as the upgrade

**Status:** accepted (2026-07-07)

## Decision

V0 encrypts the iCloud backup with HKDF(random 32-byte secret stored in the
**synchronized iCloud Keychain**). The preferred end state — a passkey scoped
to `wallet.taprootwizards.com` with the **PRF extension** output as the HKDF
input — ships as a follow-up behind the existing `BackupKeyProvider`
protocol.

## Why not PRF first

Unvalidated risks, each fatal to a one-tap V0 if hit late:

1. PRF requires iOS 18+ and its behavior inside a Messages extension's
   `ASAuthorizationController` presentation context is undocumented.
2. Passkey registration needs associated domains + an AASA file on a real
   domain — infrastructure V0 doesn't otherwise need.
3. PRF output must be identical across devices for restore to work; this is
   specified, but we want to verify it on hardware before betting backups on it.

The synced-keychain path gives the same UX (Face ID gate, no seed phrase,
cross-device restore via iCloud) with a weaker cryptographic story —
biometrics are enforced by the app layer, not by key derivation. See
docs/security-model.md for the exact tradeoff.

## Migration plan

New `PasskeyPRFKeyProvider` (registration on create; assertion on unlock) →
on first unlock after upgrade, decrypt with old provider, re-seal with PRF,
stamp `keyProvider: "passkey-prf"`. Keep the old provider readable for one
version window.

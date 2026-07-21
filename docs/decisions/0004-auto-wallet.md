# ADR 0004: Auto-wallet — no creation ceremony, mailbox semantics

**Status:** accepted (2026-07-12)

## Decision

There is no "Create Wallet" step and no unlock screen. Opening OrangeBubbles
silently creates the wallet (first ever open) or restores it (fresh
device with an iCloud backup). Face ID guards **spending and revealing
the recovery phrase** — not viewing the balance, not receiving.

Identity-derived keys (phone number, Apple ID → address) were considered
and rejected: public identifiers run through a shipped derivation
function are computable by anyone, so they can never be key material.
The user-facing goal — "the wallet is just there, tied to my account" —
is achieved instead with a random seed anchored to the user's iCloud.

## Mechanics

- **Local fast path:** decrypted `WalletSecrets` cached in a
  device-only keychain item (`AfterFirstUnlockThisDeviceOnly`,
  non-synchronizable). Every open after the first boots the engine with
  zero prompts and zero envelope decryptions.
- **Fresh device / reinstall:** the iCloud envelope restores as before.
  Keychain-sealed backups restore *silently* (the key syncs via iCloud
  Keychain); passkey-sealed backups show exactly one Face ID assertion —
  which is the passkey's whole point.
- **First ever open:** generate seed → seal with the silent synced-
  keychain key → write envelope to iCloud → cache locally. The user sees
  a brief "Setting things up…" spinner and then a zero-balance wallet.
- **Passkey (PRF) becomes an explicit upgrade** — Settings → "Upgrade to
  passkey protection" — because registration shows a system sheet and
  silent creation must be silent. Silent reseals (index-hint updates)
  never downgrade a passkey-sealed envelope; if no session key is in
  memory and the envelope is passkey-sealed, the reseal is skipped
  (hints go stale; the restore full-scan absorbs that).

## Security model change (supersedes part of docs/security-model.md)

| Action | Before | Now |
| --- | --- | --- |
| See balance / history | Face ID (unlock) | Unlocked device is enough |
| Receive | Face ID (unlock) | Unlocked device is enough |
| Send | Face ID | Face ID (unchanged) |
| Reveal seed | Face ID | Face ID (unchanged) |
| Restore on new device | Face ID | Silent (keychain) / one Face ID (passkey) |

Rationale: balance visibility on an unlocked phone equals the bar of
Messages itself (the transcript already shows payment cards) and of
mainstream fintech apps. What Face ID actually protects — irreversible
movement of funds and the seed — is unchanged. The local secrets cache
is passcode/SEP-protected at rest and never leaves the device.

Multi-device race (two devices' first-ever opens creating different
wallets before iCloud syncs) is unchanged from the ceremony era —
`backupExists()` is checked first; the residual window is accepted and
tracked in docs/backlog.md.

## Revisit when

- Real users report unwanted balance visibility → add an optional
  "require Face ID to open" toggle (app-layer, like banking apps).
- Passkey adoption matters → consider prompting the upgrade once, at a
  moment the user is already authenticating (first send).

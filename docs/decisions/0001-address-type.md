# ADR 0001: BIP84 native SegWit as the V0 address type

**Status:** accepted (2026-07-07)

## Decision

Default to **BIP84 native SegWit** (`bc1q…`). BIP86 Taproot (`bc1p…`) is
implemented in `WalletEngine` behind `ScriptType.bip86` but not the default.

## Why

The dominant V0 flow is *other people paying this wallet* from whatever they
already use — exchanges, Cash App, older mobile wallets. bech32m send support
is still not universal there, and a failed "my friend's exchange won't let me
send to this address" moment kills the product's one-tap magic. BIP84 is
universally sendable-to, and fee differences are negligible at chat-wallet
amounts.

## Revisit when

Exchange bech32m support is effectively universal, or we want
Taproot-specific features. Migration = new `ScriptType` default + both
descriptor sets watched for existing wallets (the backup already records
`scriptType` per wallet).

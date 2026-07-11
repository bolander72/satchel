# Backlog — considered, deliberately deferred

Parked items with their reasoning, so future-us doesn't re-litigate from
scratch. Everything here fits the no-TW-server policy or documents where
that policy bites.

## 1. Home Screen / Lock Screen widget (and Watch complication)

Glanceable balance + recent transactions without opening Messages — the
server-free answer to "can I see my balance in Apple Wallet?" (PassKit
passes can only update via a web service + APNs, i.e. a server, so Apple
Wallet is out under the policy.)

Sketch: App Group shared container; the Messages extension writes a
watch-only snapshot (balance, recent txs, timestamp — never keys) on every
refresh; a WidgetKit extension on the host app renders it with honest
"as of" freshness, optionally refreshing on iOS's ~15-min widget budget by
querying Esplora directly with watch-only addresses. Lock Screen privacy
via native widget redaction (blur until Face ID). Bonus: gives the host
app a real purpose, which App Review likes.

**Trigger to build:** after first on-device dogfooding round.

## 2. TestFlight / device-build tooling

An archive + export script (`xcodebuild archive` → `exportArchive` with an
ExportOptions.plist) and a versioning convention, so device builds and
TestFlight uploads are one command instead of Xcode clicking.

**Trigger to build:** the moment Apple Developer enrollment clears —
nothing to do before there's a team to sign with.

## 3. Dollar-denominated amount entry

We display ≈USD everywhere, but amounts are *entered* in sats. Letting
users type "$5" means choosing which number is authoritative when the rate
moves between typing and broadcast, and stale-rate UX at send time.

**Trigger to build:** real-user feedback saying sats entry is a blocker —
not before; the ambiguity cost is real and the workaround (glance at the
≈USD line while typing) is decent.

## 4. Multi-device same-wallet writes — accepted behavior

Two iPhones on one Apple ID can both unlock the wallet and race the backup
reseal (last writer wins; `NSFileCoordinator` prevents torn writes; the
`.previous` envelope generation protects against a bad seal). Worst case
is stale receive/change index *hints*, which the restore full-scan (stop
gap 25) absorbs. Funds are never at risk; duplicate address handout across
two devices used simultaneously is possible but harmless (both are ours).

**Decision:** accepted for V1. Revisit only if support data shows real
users actively sending from two devices at once — the fix (conflict-aware
envelope merging) isn't worth its complexity today.

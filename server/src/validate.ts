/**
 * Loose syntactic validation only — enough to keep the proxy from being used
 * as an open relay to arbitrary upstream paths. Real validation happens on
 * the Bitcoin network; the client (BDK) already produces canonical values.
 */

const BECH32 = /^(bc1|tb1|bcrt1)[02-9ac-hj-np-z]{11,87}$/i;
const BASE58 = /^[123mn][1-9A-HJ-NP-Za-km-z]{25,39}$/;

export function isPlausibleBitcoinAddress(s: string): boolean {
  return BECH32.test(s) || BASE58.test(s);
}

export function isTxid(s: string): boolean {
  return /^[0-9a-f]{64}$/i.test(s);
}

export function isRawTxHex(s: string): boolean {
  // Minimum plausible tx is well over 60 bytes; cap at 400kB hex (standardness limit region).
  return s.length >= 120 && s.length <= 800_000 && s.length % 2 === 0 && /^[0-9a-f]+$/i.test(s);
}

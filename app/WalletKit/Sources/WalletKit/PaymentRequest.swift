import Foundation

/// A BIP21-style payment request — what travels inside an iMessage card's
/// URL and what the Receive/Send screens exchange.
public struct PaymentRequest: Equatable, Sendable {
    public var address: String
    public var amountSats: UInt64?
    public var label: String?
    /// Set once the payer has broadcast; lets a reopened card show status.
    public var txid: String?

    public init(address: String, amountSats: UInt64? = nil, label: String? = nil, txid: String? = nil) {
        self.address = address
        self.amountSats = amountSats
        self.label = label
        self.txid = txid
    }

    /// bitcoin:bc1q…?amount=0.00010000&label=…
    public var bip21URI: String {
        var uri = "bitcoin:\(address)"
        var params: [String] = []
        if let amountSats {
            params.append("amount=\(Self.btcString(sats: amountSats))")
        }
        if let label, !label.isEmpty,
           let encoded = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            params.append("label=\(encoded)")
        }
        if !params.isEmpty { uri += "?" + params.joined(separator: "&") }
        return uri
    }

    /// Round-trips through the MSMessage URL (query-item encoding).
    public func queryItems() -> [URLQueryItem] {
        var items = [URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "address", value: address)]
        if let amountSats { items.append(URLQueryItem(name: "sats", value: String(amountSats))) }
        if let label, !label.isEmpty { items.append(URLQueryItem(name: "label", value: label)) }
        if let txid { items.append(URLQueryItem(name: "txid", value: txid)) }
        return items
    }

    public init?(queryItems: [URLQueryItem]) {
        func value(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }
        guard let address = value("address"), !address.isEmpty else { return nil }
        self.address = address
        self.amountSats = value("sats").flatMap(UInt64.init)
        self.label = value("label")
        self.txid = value("txid")
    }

    public static func btcString(sats: UInt64) -> String {
        let whole = sats / 100_000_000
        let frac = sats % 100_000_000
        return String(format: "%d.%08d", whole, frac)
    }

    public static func formatSats(_ sats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let n = formatter.string(from: NSNumber(value: sats)) ?? String(sats)
        return "\(n) sats"
    }
}

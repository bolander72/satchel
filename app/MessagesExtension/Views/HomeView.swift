import SwiftUI
import WalletKit

struct HomeView: View {
    @ObservedObject var store: WalletStore
    @ObservedObject var bridge: ExtensionBridge

    @State private var showReceive = false
    @State private var showSend = false

    var body: some View {
        VStack(spacing: 0) {
            balanceHeader
                .padding(.top, 12)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    bridge.requestExpanded()
                    showReceive = true
                } label: {
                    Label("Receive", systemImage: "arrow.down.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    bridge.requestExpanded()
                    showSend = true
                } label: {
                    Label("Send", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.balance.totalSats == 0)
            }
            .controlSize(.regular)
            .padding()

            if !bridge.isCompact {
                transactionList
            }

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showReceive) {
            ReceiveView(store: store, bridge: bridge)
        }
        .sheet(isPresented: $showSend) {
            SendView(store: store, bridge: bridge, prefill: nil)
        }
        .sheet(item: incomingSendRequest) { card in
            SendView(store: store, bridge: bridge, prefill: card.request)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    /// Tapped payment-request cards open Send prefilled; receipts are ignored here.
    private var incomingSendRequest: Binding<IncomingCard?> {
        Binding(
            get: {
                guard let card = store.incomingRequest, !card.isReceipt else { return nil }
                return card
            },
            set: { if $0 == nil { store.incomingRequest = nil } }
        )
    }

    private var balanceHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(PaymentRequest.formatSats(store.balance.totalSats))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                if store.isSyncing {
                    ProgressView().controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Text("\(PaymentRequest.btcString(sats: store.balance.totalSats)) BTC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if store.balance.pendingSats > 0 {
                    Text("\(PaymentRequest.formatSats(store.balance.pendingSats)) pending")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if store.chain.network != .bitcoin {
                    NetworkBadge(network: store.chain.network)
                }
            }
        }
    }

    private var transactionList: some View {
        Group {
            if store.transactions.isEmpty {
                VStack(spacing: 6) {
                    Text("No activity yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap Receive to share an address in this chat.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            } else {
                List(store.transactions) { tx in
                    TransactionRow(tx: tx, explorerURL: store.chain.explorerURL(txid: tx.txid))
                }
                .listStyle(.plain)
            }
        }
    }
}

struct TransactionRow: View {
    let tx: WalletTransaction
    let explorerURL: URL

    var body: some View {
        HStack {
            Image(systemName: tx.direction == .incoming ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .foregroundStyle(tx.direction == .incoming ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.direction == .incoming ? "Received" : "Sent")
                    .font(.subheadline.weight(.medium))
                Text(tx.confirmed ? (tx.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Confirmed") : "Pending confirmation")
                    .font(.caption)
                    .foregroundStyle(tx.confirmed ? Color.secondary : Color.orange)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text((tx.direction == .incoming ? "+" : "−") + PaymentRequest.formatSats(tx.amountSats))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.direction == .incoming ? .green : .primary)
                Link("View", destination: explorerURL)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

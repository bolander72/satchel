import SwiftUI
import WalletKit

struct SendView: View {
    @ObservedObject var store: WalletStore
    @ObservedObject var bridge: ExtensionBridge
    let prefill: PaymentRequest?

    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case compose
        case review(SignedSend)
        case broadcasting
        case sent(txid: String, details: PreparedSend)
    }

    @State private var stage: Stage = .compose
    @State private var address = ""
    @State private var amountText = ""
    @State private var feeChoice: FeeChoice = .normal
    @State private var working = false

    enum FeeChoice: String, CaseIterable, Identifiable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
        var id: String { rawValue }

        func satPerVb(_ tiers: FeeTiers) -> UInt64 {
            switch self {
            case .slow: return max(tiers.hourFee, tiers.minimumFee)
            case .normal: return max(tiers.halfHourFee, tiers.minimumFee)
            case .fast: return max(tiers.fastestFee, tiers.minimumFee)
            }
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Send Bitcoin")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(doneButtonTitle) { dismiss() }
                    }
                }
        }
        .onAppear {
            if let prefill {
                address = prefill.address
                if let sats = prefill.amountSats { amountText = String(sats) }
            }
        }
        .interactiveDismissDisabled(isMidFlight)
    }

    private var doneButtonTitle: String {
        if case .sent = stage { return "Done" }
        return "Cancel"
    }

    private var isMidFlight: Bool {
        switch stage {
        case .broadcasting: return true
        default: return working
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .compose:
            composeForm
        case .review(let send):
            reviewSheet(send)
        case .broadcasting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Broadcasting…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sent(let txid, let details):
            sentView(txid: txid, details: details)
        }
    }

    // MARK: - Compose

    private var composeForm: some View {
        Form {
            Section("To") {
                TextField("Bitcoin address", text: $address, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if let prefill, prefill.address == address, let label = prefill.label, !label.isEmpty {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Amount") {
                TextField("Amount in sats", text: $amountText)
                    .keyboardType(.numberPad)
                if let sats = parsedAmount {
                    Text("\(PaymentRequest.btcString(sats: sats)) BTC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Available: \(PaymentRequest.formatSats(store.balance.confirmedSats))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Network fee") {
                Picker("Speed", selection: $feeChoice) {
                    ForEach(FeeChoice.allCases) { choice in
                        Text("\(choice.rawValue) · \(choice.satPerVb(store.feeTiers)) sat/vB").tag(choice)
                    }
                }
                .pickerStyle(.menu)
            }

            if isLargeSend {
                Section {
                    Label(
                        "This sends most of your balance. Double-check the address — Bitcoin payments can't be reversed.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    Task { await prepare() }
                } label: {
                    if working {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Review with Face ID", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canReview || working)
            }
        }
    }

    private var parsedAmount: UInt64? {
        UInt64(amountText.filter(\.isNumber)).flatMap { $0 > 0 ? $0 : nil }
    }

    private var canReview: Bool {
        parsedAmount != nil && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLargeSend: Bool {
        guard let sats = parsedAmount, store.balance.confirmedSats > 0 else { return false }
        return Double(sats) / Double(store.balance.confirmedSats) > 0.75
    }

    private func prepare() async {
        guard let sats = parsedAmount else { return }
        working = true
        defer { working = false }
        do {
            let send = try await store.prepareSend(
                to: address.trimmingCharacters(in: .whitespacesAndNewlines),
                amountSats: sats,
                feeRateSatPerVb: feeChoice.satPerVb(store.feeTiers)
            )
            stage = .review(send)
        } catch {
            store.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: - Review

    private func reviewSheet(_ send: SignedSend) -> some View {
        Form {
            Section("Confirm payment") {
                row("To", send.details.destinationAddress, monospaced: true)
                row("Amount", PaymentRequest.formatSats(send.details.amountSats))
                row("Network fee", PaymentRequest.formatSats(send.details.feeSats))
                row("Total", PaymentRequest.formatSats(send.details.totalSats))
            }

            Section {
                Button {
                    Task { await broadcast(send) }
                } label: {
                    Label("Send now", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                Button("Back", role: .cancel) { stage = .compose }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .body)
        }
    }

    private func broadcast(_ send: SignedSend) async {
        stage = .broadcasting
        do {
            let txid = try await store.broadcast(send)
            stage = .sent(txid: txid, details: send.details)
        } catch {
            store.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            stage = .review(send)
        }
    }

    // MARK: - Sent

    private func sentView(txid: String, details: PreparedSend) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Sent \(PaymentRequest.formatSats(details.amountSats))")
                .font(.headline)
            Link("View transaction", destination: store.chain.explorerURL(txid: txid))
                .font(.subheadline)

            Button {
                let receipt = PaymentRequest(
                    address: details.destinationAddress,
                    amountSats: details.amountSats,
                    txid: txid
                )
                bridge.insertCard(for: receipt, kind: .sent)
                dismiss()
            } label: {
                Label("Share receipt in chat", systemImage: "message.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

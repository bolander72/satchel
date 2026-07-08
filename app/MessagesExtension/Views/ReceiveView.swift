import SwiftUI
import WalletKit

struct ReceiveView: View {
    @ObservedObject var store: WalletStore
    @ObservedObject var bridge: ExtensionBridge
    @Environment(\.dismiss) private var dismiss

    @State private var request: PaymentRequest?
    @State private var amountText = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let request {
                        card(for: request)
                    } else {
                        ProgressView().padding(.top, 48)
                    }
                }
                .padding()
            }
            .navigationTitle("Receive Bitcoin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await deriveAddress() }
    }

    @ViewBuilder
    private func card(for request: PaymentRequest) -> some View {
        if let qr = QRCodeGenerator.image(for: request.bip21URI) {
            Image(uiImage: qr)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        }

        Button {
            UIPasteboard.general.string = request.address
            copied = true
        } label: {
            VStack(spacing: 4) {
                Text(request.address)
                    .font(.system(.footnote, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                Text(copied ? "Copied!" : "Tap to copy")
                    .font(.caption2)
                    .foregroundStyle(copied ? .green : .secondary)
            }
        }
        .buttonStyle(.plain)

        HStack {
            TextField("Amount in sats (optional)", text: $amountText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: amountText) { _, _ in applyAmount() }
        }

        Button {
            var final = request
            final.label = "Wizard Wallet request"
            bridge.insertCard(for: final, kind: .request)
            dismiss()
        } label: {
            Label("Share in chat", systemImage: "message.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Text("This address is fresh — it hasn't been used before. Reuse hurts privacy, so tap Receive again next time.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private func deriveAddress() async {
        guard request == nil else { return }
        do {
            request = try await store.makeReceiveRequest(amountSats: nil, label: nil)
        } catch {
            store.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            dismiss()
        }
    }

    private func applyAmount() {
        guard var current = request else { return }
        current.amountSats = UInt64(amountText.filter(\.isNumber))
        request = current
    }
}

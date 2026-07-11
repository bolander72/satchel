import SwiftUI
import WalletKit

struct RootView: View {
    @ObservedObject var store: WalletStore
    @ObservedObject var bridge: ExtensionBridge

    var body: some View {
        ZStack {
            switch store.phase {
            case .loading:
                ProgressView()
            case .welcome(let hasBackup):
                WelcomeView(store: store, bridge: bridge, hasBackup: hasBackup)
            case .working(let message):
                WorkingView(message: message)
            case .ready:
                HomeView(store: store, bridge: bridge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Brand.orange)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct WorkingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Brand.orange)
            Text(message)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var store: WalletStore
    @ObservedObject var bridge: ExtensionBridge
    let hasBackup: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            BitcoinMark(size: bridge.isCompact ? 52 : 72)
                .padding(.bottom, bridge.isCompact ? 10 : 18)

            Text(hasBackup ? "Welcome back" : "Bitcoin, right here in Messages")
                .font(.system(bridge.isCompact ? .headline : .title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)

            if !bridge.isCompact {
                Text(
                    hasBackup
                        ? "Your wallet backup is ready. Unlock it with Face ID."
                        : "One tap. No seed phrases, no sign-ups.\nBacked up privately to your iCloud."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 8)
            }

            Button {
                Task { await expandThen { hasBackup ? await store.restoreWallet() : await store.createWallet() } }
            } label: {
                Label(
                    hasBackup ? "Unlock with Face ID" : "Create Bitcoin Wallet",
                    systemImage: "faceid"
                )
            }
            .buttonStyle(ProminentButtonStyle())
            .padding(.top, bridge.isCompact ? 14 : 22)

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Keys never leave your device")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                NetworkBadge(network: store.chain.network)
            }
            .foregroundStyle(.tertiary)
            .padding(.top, 12)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
    }

    /// Face ID cannot survive a compact→expanded transition happening
    /// underneath it (LAError -4 systemCancel), so expand first, let the
    /// Messages presentation settle, then start the authenticated flow.
    private func expandThen(_ action: @escaping () async -> Void) async {
        if bridge.isCompact {
            bridge.requestExpanded()
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        await action()
    }
}

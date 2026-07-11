import SwiftUI
import WalletKit

// MARK: - Brand

enum Brand {
    /// Bitcoin orange. Used for primary actions and incoming amounts only —
    /// everything else stays in system neutrals so the orange means something.
    static let orange = Color(red: 0.97, green: 0.58, blue: 0.10)
    static let orangeDeep = Color(red: 0.93, green: 0.42, blue: 0.05)

    /// Reserved for brand moments: welcome hero, balance numerals, QR frame.
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [orange, orangeDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var subtleGradient: LinearGradient {
        LinearGradient(
            colors: [orange.opacity(0.14), orangeDeep.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Formatting

enum Format {
    static func sats(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func btc(_ sats: UInt64) -> String {
        PaymentRequest.btcString(sats: sats)
    }

    /// tb1q9ykh…jw48dpq — enough of both ends to eyeball-verify.
    static func shortAddress(_ address: String, prefix: Int = 10, suffix: Int = 7) -> String {
        guard address.count > prefix + suffix + 1 else { return address }
        return "\(address.prefix(prefix))…\(address.suffix(suffix))"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Buttons

struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Brand.gradient)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(Brand.orangeDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Brand.orange.opacity(0.13))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Small pieces

/// Circular icon well used by transaction rows and info banners.
struct IconBubble: View {
    let systemName: String
    var tint: Color = Brand.orange
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.14)))
    }
}

struct NetworkBadge: View {
    let network: NetworkKind

    var body: some View {
        if network != .bitcoin {
            Text(network.rawValue.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.purple.opacity(0.14)))
                .foregroundStyle(.purple)
        }
    }
}

struct InfoBanner: View {
    let systemName: String
    let text: String
    var tint: Color = .orange

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }
}

/// The ₿ mark used on welcome, cards, and success states.
struct BitcoinMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.gradient)
                .frame(width: size, height: size)
                .shadow(color: Brand.orange.opacity(0.35), radius: size * 0.18, y: size * 0.08)
            Image(systemName: "bitcoinsign")
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

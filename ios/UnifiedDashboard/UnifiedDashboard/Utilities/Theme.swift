import SwiftUI

// MARK: - Color Palette

extension Color {
    // Backgrounds
    static let portalBg = Color(red: 0.04, green: 0.055, blue: 0.08)
    static let cardBg = Color(red: 0.067, green: 0.094, blue: 0.125)
    static let cardBorder = Color.white.opacity(0.07)
    static let elevatedBg = Color(red: 0.08, green: 0.11, blue: 0.15)

    // Accents
    static let portalBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let portalGreen = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let portalRed = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let portalOrange = Color(red: 0.96, green: 0.62, blue: 0.04)

    // Text
    static let textPrimary = Color(red: 0.89, green: 0.91, blue: 0.94)
    static let textDim = Color(red: 0.53, green: 0.60, blue: 0.67)
}

// MARK: - Card Modifier

struct CardStyle: ViewModifier {
    var accentColor: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.cardBorder, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if let accent = accentColor {
                    accent
                        .frame(width: 3)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 14, bottomLeadingRadius: 14
                        ))
                }
            }
    }
}

extension View {
    func cardStyle(accent: Color? = nil) -> some View {
        modifier(CardStyle(accentColor: accent))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.textDim)
            }
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.textDim)
                .tracking(1)
        }
    }
}

// MARK: - Stat Pill (for inline stats)

struct StatPill: View {
    let label: String
    let value: String
    var color: Color = .textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.textDim)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Glow Header (hero number)

struct GlowNumber: View {
    let label: String
    let value: String
    var color: Color = .textPrimary
    var subtitle: String? = nil
    var icon: String = "chart.line.uptrend.xyaxis"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: label + icon
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.textDim)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }

            // Hero number with glow
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 2)
                .shadow(color: color.opacity(0.1), radius: 20, x: 0, y: 4)

            // Subtitle
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityValue(subtitle ?? "")
    }
}

// MARK: - Loading Placeholder

struct LoadingCard: View {
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 14) {
            // Fake header bar
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.textDim.opacity(0.08))
                .frame(height: 14)
                .frame(maxWidth: 120, alignment: .leading)
            // Fake hero number
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.textDim.opacity(0.06))
                .frame(height: 32)
                .frame(maxWidth: 200, alignment: .leading)
            // Fake subtitle
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.textDim.opacity(0.05))
                .frame(height: 12)
                .frame(maxWidth: 160, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .opacity(shimmer ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
        .cardStyle()
    }
}

// MARK: - Empty State

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.textDim.opacity(0.5))
            Text(title)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundStyle(.textDim)
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.textDim.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 13))
                .foregroundStyle(.portalRed)
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.portalRed)
                .lineLimit(2)
            Spacer()
            if let onRetry {
                Button {
                    Haptic.tap()
                    onRetry()
                } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.portalRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.portalRed.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.portalRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.portalRed.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Haptics

enum Haptic {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

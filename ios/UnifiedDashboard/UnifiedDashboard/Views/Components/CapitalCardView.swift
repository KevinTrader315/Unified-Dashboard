import SwiftUI

struct CapitalCardView: View {
    let account: CapitalAccount
    var onRemove: (() -> Void)? = nil

    private var accentColor: Color { Fmt.hexColor(account.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: bot name + P&L
            HStack(alignment: .top) {
                Text(account.label)
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text(Fmt.signedDollars(account.pnl))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Fmt.pnlColorCents(account.pnl))
            }

            // Effective balance (hero)
            Text(Fmt.dollars(account.effective))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(.textPrimary)

            // Allocation subtitle
            Text("\(Fmt.dollars(account.allocation)) allocated")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.textDim)

            // Progress bar
            GeometryReader { geo in
                let fraction = account.allocation > 0
                    ? min(1.0, Double(account.effective) / Double(account.allocation))
                    : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.cardBorder)
                        .frame(height: 4)
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(4, geo.size.width * fraction), height: 4)
                }
            }
            .frame(height: 4)
        }
        .cardStyle(accent: accentColor)
    }
}

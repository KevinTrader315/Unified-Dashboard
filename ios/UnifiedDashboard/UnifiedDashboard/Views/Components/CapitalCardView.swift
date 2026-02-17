import SwiftUI

struct CapitalCardView: View {
    let account: CapitalAccount
    let totalAllocated: Int
    var onRemove: (() -> Void)? = nil

    private var accentColor: Color { Fmt.hexColor(account.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: bot name + labeled P&L
            HStack(alignment: .firstTextBaseline) {
                Text(account.label)
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text("P&L")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.textDim)
                    Text(Fmt.signedDollars(account.pnl))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Fmt.pnlColorCents(account.pnl))
                }
            }

            // Effective balance (hero)
            Text(Fmt.dollars(account.effective))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(.textPrimary)

            // Allocation subtitle
            Text("\(Fmt.dollars(account.allocation)) allocated")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.textDim)

            // Progress bar — fraction of total capital this bot uses
            GeometryReader { geo in
                let fraction = totalAllocated > 0
                    ? min(1.0, max(0, Double(account.allocation) / Double(totalAllocated)))
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
        .contextMenu {
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove Allocation", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.label), balance \(Fmt.dollars(account.effective))")
        .accessibilityValue("P&L \(Fmt.signedDollars(account.pnl)), \(Fmt.dollars(account.allocation)) allocated")
        .accessibilityHint(onRemove != nil ? "Long press to remove allocation" : "")
    }
}

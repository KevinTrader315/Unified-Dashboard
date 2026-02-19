import SwiftUI

struct BotCardView: View {
    let botId: String
    let bot: BotStatus

    private var accentColor: Color { Fmt.hexColor(bot.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(alignment: .top) {
                Text(bot.name)
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                healthBadge
            }

            if let error = bot.error {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(Color.portalRed.opacity(0.8))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.portalRed.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Hero P&L
                Text(Fmt.pnl(bot.pnl))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Fmt.pnlColor(bot.pnl))
                    .shadow(color: Fmt.pnlColor(bot.pnl).opacity(0.25), radius: 6, x: 0, y: 2)
                    .shadow(color: Fmt.pnlColor(bot.pnl).opacity(0.08), radius: 16, x: 0, y: 4)

                // Stats row
                Divider().overlay(Color.cardBorder)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    if let wr = bot.winRate {
                        StatPill(label: "WIN RATE", value: "\(String(format: "%.1f", wr))%",
                                 color: wr >= 50 ? .portalGreen : .portalOrange)
                    }
                    if let trades = bot.completed {
                        let winsStr = bot.wins.map { "/\($0)W" } ?? ""
                        StatPill(label: "TRADES", value: "\(trades)\(winsStr)")
                    }
                    if let open = bot.openPositions {
                        StatPill(label: "OPEN POS", value: "\(open)")
                    }
                    if let daily = bot.dailyTrades {
                        StatPill(label: "TODAY", value: "\(daily)")
                    }
                    if let running = bot.running {
                        StatPill(label: "ENGINE", value: running ? "Running" : "Stopped",
                                 color: running ? .portalGreen : .portalRed)
                    }
                }
            }
        }
        .cardStyle(accent: accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bot.name), \(bot.error != nil ? "offline" : (bot.healthy ? "healthy" : "issue"))")
        .accessibilityValue(bot.error ?? "P&L \(Fmt.pnl(bot.pnl))")
    }

    private var healthBadge: some View {
        let isError = bot.error != nil
        let label = isError ? "OFFLINE" : (bot.healthy ? "HEALTHY" : "ISSUE")
        let dotColor: Color = isError ? .textDim : (bot.healthy ? .portalGreen : .portalRed)
        let bgColor: Color = isError ? .textDim.opacity(0.1) : (bot.healthy ? .portalGreen.opacity(0.1) : .portalRed.opacity(0.1))

        return HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(dotColor)
                .tracking(0.3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bgColor)
        .clipShape(Capsule())
    }
}

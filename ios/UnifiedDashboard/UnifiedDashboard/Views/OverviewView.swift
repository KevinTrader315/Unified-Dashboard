import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var settings: ServerSettings
    @State private var overview: OverviewResponse?
    @State private var error: String?
    @State private var lastUpdated: Date?
    @State private var refreshTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var cardsAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Screen header
                HStack {
                    Text("Portfolio")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    if let lastUpdated {
                        Text(lastUpdated, style: .relative)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.textDim)
                    }
                }
                .padding(.top, 4)

                if isLoading && overview == nil {
                    LoadingCard()
                    LoadingCard()
                } else if let overview {
                    // Hero P&L
                    let botCount = overview.bots.count
                    GlowNumber(
                        label: "Total P&L",
                        value: Fmt.pnl(overview.totalPnl),
                        color: Fmt.pnlColor(overview.totalPnl),
                        subtitle: "\(botCount) bot\(botCount == 1 ? "" : "s") active"
                    )
                    .offset(y: cardsAppeared ? 0 : 12)
                    .opacity(cardsAppeared ? 1 : 0)

                    // Bot cards
                    let sortedBots = overview.bots.sorted(by: { $0.key < $1.key })
                    ForEach(Array(sortedBots.enumerated()), id: \.element.key) { index, pair in
                        var mutBot = pair.value
                        mutBot.id = pair.key
                        BotCardView(botId: pair.key, bot: mutBot)
                            .offset(y: cardsAppeared ? 0 : CGFloat(16 + index * 4))
                            .opacity(cardsAppeared ? 1 : 0)
                    }
                }

                if let error {
                    ErrorBanner(message: error) {
                        Task { await fetchOnce() }
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.3), value: overview?.totalPnl)
        }
        .background(Color.portalBg)
        .refreshable { await fetchOnce() }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTask = Task {
            while !Task.isCancelled {
                await fetchOnce()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func fetchOnce() async {
        let client = APIClient(settings: settings)
        do {
            var response = try await client.fetchOverview()
            var updatedBots: [String: BotStatus] = [:]
            for (key, var bot) in response.bots {
                bot.id = key
                updatedBots[key] = bot
            }
            response = OverviewResponse(bots: updatedBots, totalPnl: response.totalPnl)
            await MainActor.run {
                let wasLoading = self.isLoading
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.overview = response
                    self.lastUpdated = Date()
                    self.error = nil
                    self.isLoading = false
                }
                if wasLoading {
                    withAnimation(.easeOut(duration: 0.5).delay(0.05)) {
                        self.cardsAppeared = true
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

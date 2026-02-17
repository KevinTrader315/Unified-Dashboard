import SwiftUI

struct CapitalView: View {
    @EnvironmentObject var settings: ServerSettings
    @State private var capital: CapitalResponse?
    @State private var transfers: [Transfer] = []
    @State private var error: String?
    @State private var lastUpdated: Date?
    @State private var refreshTask: Task<Void, Never>?
    @State private var isLoading = true

    // Allocate form
    @State private var allocBotId = ""
    @State private var allocLabel = ""
    @State private var allocAmount = ""
    @State private var allocFeedback = ""
    @State private var allocIsError = false

    // Transfer form
    @State private var xferFrom = "unallocated"
    @State private var xferTo = "unallocated"
    @State private var xferAmount = ""
    @State private var xferFeedback = ""
    @State private var xferIsError = false

    @State private var showAllocateSheet = false
    @State private var showTransferSheet = false
    @State private var showAllTransfers = false
    @State private var cardsAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Screen header
                HStack {
                    Text("Capital")
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

                if isLoading && capital == nil {
                    LoadingCard()
                    LoadingCard()
                } else {
                    balanceHeader
                        .offset(y: cardsAppeared ? 0 : 12)
                        .opacity(cardsAppeared ? 1 : 0)

                    // Total P&L summary
                    if let accounts = capital?.accounts, !accounts.isEmpty {
                        let totalPnl = accounts.reduce(0) { $0 + $1.pnl }
                        HStack(spacing: 8) {
                            Image(systemName: totalPnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Fmt.pnlColorCents(totalPnl))
                            Text("Total P&L: \(Fmt.signedDollars(totalPnl))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Fmt.pnlColorCents(totalPnl))
                            Spacer()
                            Text("\(accounts.count) bot\(accounts.count == 1 ? "" : "s")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.textDim)
                        }
                        .padding(.horizontal, 4)
                        .offset(y: cardsAppeared ? 0 : 12)
                        .opacity(cardsAppeared ? 1 : 0)
                    }

                    accountCards
                        .offset(y: cardsAppeared ? 0 : 16)
                        .opacity(cardsAppeared ? 1 : 0)

                    actionButtons
                        .offset(y: cardsAppeared ? 0 : 20)
                        .opacity(cardsAppeared ? 1 : 0)

                    transferHistorySection
                        .offset(y: cardsAppeared ? 0 : 24)
                        .opacity(cardsAppeared ? 1 : 0)
                }

                if let error {
                    ErrorBanner(message: error) {
                        Task { await fetchAll() }
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.3), value: capital?.totalAllocated)
        }
        .background(Color.portalBg)
        .refreshable { await fetchAll() }
        .sheet(isPresented: $showAllocateSheet) { allocateSheet }
        .sheet(isPresented: $showTransferSheet) { transferSheet }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Balance header

    private var balanceHeader: some View {
        Group {
            if let balance = capital?.realBalance {
                GlowNumber(
                    label: "Kalshi Account",
                    value: Fmt.dollars(balance),
                    color: .textPrimary,
                    subtitle: capital?.unallocated.map { "Unallocated: \(Fmt.dollars($0))" } ?? "USD",
                    icon: "dollarsign.circle.fill"
                )
            } else {
                GlowNumber(
                    label: "Kalshi Account",
                    value: Fmt.dollars(capital?.totalAllocated ?? 0),
                    color: .textPrimary,
                    subtitle: "\(capital?.accounts.count ?? 0) bot\((capital?.accounts.count ?? 0) == 1 ? "" : "s") allocated",
                    icon: "dollarsign.circle.fill"
                )
            }
        }
    }

    // MARK: - Account cards

    private var accountCards: some View {
        Group {
            if let accounts = capital?.accounts, accounts.isEmpty {
                VStack(spacing: 6) {
                    EmptyState(
                        icon: "tray",
                        title: "No Allocations",
                        message: "Tap \"Allocate\" to assign capital to a bot"
                    )
                }
                .cardStyle()
            } else {
                ForEach(capital?.accounts ?? []) { account in
                    CapitalCardView(
                        account: account,
                        totalAllocated: capital?.totalAllocated ?? 0
                    ) {
                        Task { await removeAllocation(account.id) }
                    }
                }
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Haptic.tap()
                showAllocateSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Allocate")
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [.portalGreen, .portalGreen.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                Haptic.tap()
                showTransferSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 14))
                    Text("Transfer")
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [.portalBlue, .portalBlue.opacity(0.8)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Transfer history

    private var visibleTransfers: [Transfer] {
        showAllTransfers ? transfers : Array(transfers.prefix(3))
    }

    private var transferHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "RECENT TRANSFERS", icon: "clock.arrow.circlepath")
                Spacer()
                if transfers.count > 3 {
                    Text("\(transfers.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.portalBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.portalBlue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            if transfers.isEmpty {
                EmptyState(
                    icon: "arrow.left.arrow.right",
                    title: "No transfers yet",
                    message: "Transfers between accounts will appear here"
                )
            } else {
                ForEach(visibleTransfers) { t in
                    let isToPool = t.to == "unallocated"
                    HStack(spacing: 10) {
                        Image(systemName: isToPool ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isToPool ? .portalGreen.opacity(0.7) : .portalBlue.opacity(0.7))
                            .frame(width: 22, height: 22)
                            .background(
                                (isToPool ? Color.portalGreen : .portalBlue).opacity(0.08)
                            )
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(displayName(t.from))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.textPrimary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.textDim)
                                Text(displayName(t.to))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.textPrimary)
                            }
                            Text(Fmt.timestamp(t.ts))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.textDim)
                        }

                        Spacer()

                        Text(Fmt.dollars(t.amount))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(isToPool ? .portalGreen : .textPrimary)
                    }
                    .padding(.vertical, 6)

                    if t.id != visibleTransfers.last?.id {
                        Divider().overlay(Color.cardBorder)
                    }
                }

                // Show All / Show Less toggle
                if transfers.count > 3 {
                    Button {
                        Haptic.tap()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showAllTransfers.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showAllTransfers ? "Show Less" : "Show All \(transfers.count)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Image(systemName: showAllTransfers ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.portalBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Allocate sheet

    private var allocateSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bot ID (e.g. btc-range)", text: $allocBotId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Label (e.g. BTC Range)", text: $allocLabel)
                } header: {
                    Text("Bot")
                        .foregroundStyle(.textDim)
                }
                .listRowBackground(Color.elevatedBg)

                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.textDim)
                        TextField("0.00", text: $allocAmount)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Amount")
                        .foregroundStyle(.textDim)
                }
                .listRowBackground(Color.elevatedBg)

                if !allocFeedback.isEmpty {
                    Section {
                        Label(allocFeedback, systemImage: allocIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(allocIsError ? .portalRed : .portalGreen)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .listRowBackground(
                        (allocIsError ? Color.portalRed : .portalGreen).opacity(0.08)
                    )
                }

                Section {
                    Button {
                        Task { await doAllocate() }
                    } label: {
                        Text("Allocate Capital")
                            .frame(maxWidth: .infinity)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .disabled(allocBotId.isEmpty || allocLabel.isEmpty || allocAmount.isEmpty)
                    .listRowBackground(
                        (allocBotId.isEmpty || allocLabel.isEmpty || allocAmount.isEmpty)
                            ? Color.portalGreen.opacity(0.3)
                            : Color.portalGreen
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.portalBg)
            .foregroundStyle(.textPrimary)
            .navigationTitle("Allocate Capital")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAllocateSheet = false }
                }
            }
        }
        .presentationBackground(Color.portalBg)
    }

    // MARK: - Transfer sheet

    private var transferSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $xferFrom) {
                        Text("Unallocated").tag("unallocated")
                        ForEach(capital?.accounts ?? []) { a in
                            Text("\(a.label) (\(Fmt.dollars(a.allocation)))").tag(a.id)
                        }
                    }
                } header: {
                    Text("From")
                        .foregroundStyle(.textDim)
                }
                .listRowBackground(Color.elevatedBg)

                Section {
                    Picker("Destination", selection: $xferTo) {
                        Text("Unallocated").tag("unallocated")
                        ForEach(capital?.accounts ?? []) { a in
                            Text("\(a.label) (\(Fmt.dollars(a.allocation)))").tag(a.id)
                        }
                    }
                } header: {
                    Text("To")
                        .foregroundStyle(.textDim)
                }
                .listRowBackground(Color.elevatedBg)

                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.textDim)
                        TextField("0.00", text: $xferAmount)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Amount")
                        .foregroundStyle(.textDim)
                }
                .listRowBackground(Color.elevatedBg)

                if !xferFeedback.isEmpty {
                    Section {
                        Label(xferFeedback, systemImage: xferIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(xferIsError ? .portalRed : .portalGreen)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .listRowBackground(
                        (xferIsError ? Color.portalRed : .portalGreen).opacity(0.08)
                    )
                }

                Section {
                    Button {
                        Task { await doTransfer() }
                    } label: {
                        Text("Transfer Funds")
                            .frame(maxWidth: .infinity)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .disabled(xferFrom == xferTo || xferAmount.isEmpty)
                    .listRowBackground(
                        (xferFrom == xferTo || xferAmount.isEmpty)
                            ? Color.portalBlue.opacity(0.3)
                            : Color.portalBlue
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.portalBg)
            .foregroundStyle(.textPrimary)
            .navigationTitle("Transfer Funds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTransferSheet = false }
                }
            }
        }
        .presentationBackground(Color.portalBg)
    }

    // MARK: - Actions

    private func doAllocate() async {
        guard let amount = Double(allocAmount), amount >= 0 else {
            allocFeedback = "Enter a valid amount"
            allocIsError = true
            Haptic.error()
            return
        }
        let client = APIClient(settings: settings)
        do {
            try await client.allocateCapital(botId: allocBotId, label: allocLabel, amount: amount)
            allocFeedback = "Allocated $\(String(format: "%.2f", amount)) to \(allocLabel)"
            allocIsError = false
            allocAmount = ""
            Haptic.success()
            await fetchAll()
        } catch {
            allocFeedback = error.localizedDescription
            allocIsError = true
            Haptic.error()
        }
    }

    private func doTransfer() async {
        guard let amount = Double(xferAmount), amount > 0 else {
            xferFeedback = "Enter a valid amount"
            xferIsError = true
            Haptic.error()
            return
        }
        let client = APIClient(settings: settings)
        do {
            try await client.transferCapital(from: xferFrom, to: xferTo, amount: amount)
            xferFeedback = "Transfer complete"
            xferIsError = false
            xferAmount = ""
            Haptic.success()
            await fetchAll()
        } catch {
            xferFeedback = error.localizedDescription
            xferIsError = true
            Haptic.error()
        }
    }

    private func removeAllocation(_ botId: String) async {
        let client = APIClient(settings: settings)
        do {
            try await client.removeAllocation(botId: botId)
            Haptic.success()
            await fetchAll()
        } catch {
            self.error = error.localizedDescription
            Haptic.error()
        }
    }

    private func displayName(_ id: String) -> String {
        if id == "unallocated" { return "Pool" }
        return capital?.accounts.first(where: { $0.id == id })?.label ?? id
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTask = Task {
            while !Task.isCancelled {
                await fetchAll()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func fetchAll() async {
        let client = APIClient(settings: settings)
        do {
            async let cap = client.fetchCapital()
            async let xfer = client.fetchTransfers()
            let (capResult, xferResult) = try await (cap, xfer)
            await MainActor.run {
                let wasLoading = self.isLoading
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.capital = capResult
                    self.transfers = xferResult.transfers
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

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

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Drag indicator
                Capsule()
                    .fill(Color.textDim.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                if isLoading && capital == nil {
                    LoadingCard()
                } else {
                    balanceHeader
                    accountCards
                    actionButtons
                    transferHistorySection
                }

                if let error {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.portalRed)
                        Text(error)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.portalRed)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.portalRed.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    subtitle: "USD",
                    icon: "dollarsign.circle.fill"
                )
            } else {
                GlowNumber(
                    label: "Kalshi Account",
                    value: Fmt.dollars(capital?.totalAllocated ?? 0),
                    color: .textPrimary,
                    subtitle: "USD",
                    icon: "dollarsign.circle.fill"
                )
            }
        }
    }

    // MARK: - Account cards

    private var accountCards: some View {
        ForEach(capital?.accounts ?? []) { account in
            CapitalCardView(account: account) {
                Task { await removeAllocation(account.id) }
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

    private var transferHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "RECENT TRANSFERS", icon: "clock.arrow.circlepath")

            if transfers.isEmpty {
                EmptyState(
                    icon: "arrow.left.arrow.right",
                    title: "No transfers yet",
                    message: "Transfers between accounts will appear here"
                )
            } else {
                ForEach(transfers) { t in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.portalBlue.opacity(0.6))
                            .frame(width: 20)

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
                            .foregroundStyle(.textPrimary)
                    }
                    .padding(.vertical, 6)

                    if t.id != transfers.last?.id {
                        Divider().overlay(Color.cardBorder)
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
                Section("Bot") {
                    TextField("Bot ID (e.g. btc-range)", text: $allocBotId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Label (e.g. BTC Range)", text: $allocLabel)
                }
                Section("Amount") {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $allocAmount)
                            .keyboardType(.decimalPad)
                    }
                }
                if !allocFeedback.isEmpty {
                    Section {
                        Label(allocFeedback, systemImage: allocIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(allocIsError ? .red : .green)
                            .font(.caption)
                    }
                }
                Section {
                    Button {
                        Task { await doAllocate() }
                    } label: {
                        Text("Allocate Capital")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .disabled(allocBotId.isEmpty || allocLabel.isEmpty || allocAmount.isEmpty)
                }
            }
            .navigationTitle("Allocate Capital")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAllocateSheet = false }
                }
            }
        }
    }

    // MARK: - Transfer sheet

    private var transferSheet: some View {
        NavigationStack {
            Form {
                Section("From") {
                    Picker("Source", selection: $xferFrom) {
                        Text("Unallocated").tag("unallocated")
                        ForEach(capital?.accounts ?? []) { a in
                            Text("\(a.label) (\(Fmt.dollars(a.allocation)))").tag(a.id)
                        }
                    }
                }
                Section("To") {
                    Picker("Destination", selection: $xferTo) {
                        Text("Unallocated").tag("unallocated")
                        ForEach(capital?.accounts ?? []) { a in
                            Text("\(a.label) (\(Fmt.dollars(a.allocation)))").tag(a.id)
                        }
                    }
                }
                Section("Amount") {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $xferAmount)
                            .keyboardType(.decimalPad)
                    }
                }
                if !xferFeedback.isEmpty {
                    Section {
                        Label(xferFeedback, systemImage: xferIsError ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(xferIsError ? .red : .green)
                            .font(.caption)
                    }
                }
                Section {
                    Button {
                        Task { await doTransfer() }
                    } label: {
                        Text("Transfer Funds")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .disabled(xferFrom == xferTo || xferAmount.isEmpty)
                }
            }
            .navigationTitle("Transfer Funds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTransferSheet = false }
                }
            }
        }
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
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.capital = capResult
                    self.transfers = xferResult.transfers
                    self.lastUpdated = Date()
                    self.error = nil
                    self.isLoading = false
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

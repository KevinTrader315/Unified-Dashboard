import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: ServerSettings
    @State private var showSetup = false

    var body: some View {
        if settings.isConfigured && !showSetup {
            MainTabView()
                .transition(.opacity)
        } else {
            SettingsView(isInitialSetup: true)
                .transition(.opacity)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var settings: ServerSettings
    @State private var selectedTab = 0
    @State private var isConnected = true

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.055, green: 0.075, blue: 0.1, alpha: 1)

        // Top border
        appearance.shadowColor = UIColor(white: 1.0, alpha: 0.07)

        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(white: 0.4, alpha: 1)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(white: 0.4, alpha: 1),
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        ]

        // Selected state
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem {
                    Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)

            CapitalView()
                .tabItem {
                    Label("Capital", systemImage: "banknote.fill")
                }
                .tag(1)

            BotDashboardView()
                .tabItem {
                    Label("Bots", systemImage: "cpu.fill")
                }
                .tag(2)

            TerminalView()
                .tabItem {
                    Label("Terminal", systemImage: "apple.terminal.fill")
                }
                .tag(3)

            SettingsView(isInitialSetup: false)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .badge(isConnected ? 0 : 1)
                .tag(4)
        }
        .tint(.portalGreen)
        .task { await checkConnection() }
    }

    private func checkConnection() async {
        let client = APIClient(settings: settings)
        do {
            _ = try await client.fetchOverview()
            await MainActor.run { isConnected = true }
        } catch {
            await MainActor.run { isConnected = false }
        }
    }
}

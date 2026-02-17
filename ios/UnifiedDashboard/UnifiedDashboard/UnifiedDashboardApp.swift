import SwiftUI

@main
struct UnifiedDashboardApp: App {
    @StateObject private var settings = ServerSettings()
    @StateObject private var auth = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(settings)
                    .environmentObject(auth)

                if auth.isLocked {
                    LockScreenView()
                        .environmentObject(auth)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: auth.isLocked)
            .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                auth.lock()
            }
        }
    }
}

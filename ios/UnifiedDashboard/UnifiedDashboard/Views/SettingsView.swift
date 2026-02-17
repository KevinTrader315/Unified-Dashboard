import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: ServerSettings
    @EnvironmentObject var auth: AuthManager
    var isInitialSetup: Bool

    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var isTesting = false

    var body: some View {
        if isInitialSetup {
            NavigationStack {
                onboardingLayout
            }
        } else {
            settingsForm
        }
    }

    // MARK: - Onboarding (initial setup)

    private var onboardingLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                // Hero
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.portalBlue.opacity(0.2), .clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 100, height: 100)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.portalBlue)
                    }

                    Text("Connect to Portal")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .foregroundStyle(.textPrimary)

                    Text("Enter your Unified Dashboard server URL\nto start monitoring your trading bots.")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // Server URL field
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "SERVER URL", icon: "link")

                    TextField("http://192.168.1.100:8080", text: $settings.serverURL)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(14)
                        .background(Color.elevatedBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.cardBorder, lineWidth: 1)
                        )
                }

                // Auth fields
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "AUTHENTICATION", icon: "lock")
                    Text("Optional — only if your portal uses Basic Auth")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.textDim.opacity(0.6))

                    HStack(spacing: 10) {
                        TextField("Username", text: $settings.username)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.elevatedBg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.cardBorder, lineWidth: 1)
                            )

                        SecureField("Password", text: $settings.password)
                            .font(.system(.body, design: .monospaced))
                            .padding(14)
                            .background(Color.elevatedBg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.cardBorder, lineWidth: 1)
                            )
                    }
                }

                // Test button
                Button {
                    Haptic.tap()
                    Task { await testConnection() }
                } label: {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isTesting ? "Connecting..." : "Test Connection")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [.portalBlue, .portalBlue.opacity(0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!settings.isConfigured || isTesting)
                .opacity(settings.isConfigured ? 1 : 0.4)

                if let result = testResult {
                    HStack(spacing: 8) {
                        Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(result)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .foregroundStyle(testSuccess ? .portalGreen : .portalRed)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background((testSuccess ? Color.portalGreen : .portalRed).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Spacer()
            }
            .padding(24)
        }
        .background(Color.portalBg)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Settings form (non-setup)

    private var settingsForm: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Screen header (matches Portfolio/Capital/Dashboards)
                HStack {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(.textPrimary)
                    Spacer()
                }
                .padding(.top, 4)

                // Server
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "SERVER", icon: "server.rack")

                    TextField("http://192.168.1.100:8080", text: $settings.serverURL)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(14)
                        .background(Color.elevatedBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.cardBorder, lineWidth: 1)
                        )
                }
                .cardStyle()

                // Auth
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "AUTHENTICATION", icon: "lock")

                    TextField("Username", text: $settings.username)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.elevatedBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.cardBorder, lineWidth: 1)
                        )

                    SecureField("Password", text: $settings.password)
                        .font(.system(.body, design: .monospaced))
                        .padding(14)
                        .background(Color.elevatedBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.cardBorder, lineWidth: 1)
                        )
                }
                .cardStyle()

                // Test connection
                VStack(spacing: 12) {
                    Button {
                        Haptic.tap()
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(isTesting ? "Testing..." : "Test Connection")
                                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.portalBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!settings.isConfigured || isTesting)
                    .opacity(settings.isConfigured ? 1 : 0.4)

                    if let result = testResult {
                        HStack(spacing: 6) {
                            Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 12))
                            Text(result)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .foregroundStyle(testSuccess ? .portalGreen : .portalRed)
                    }
                }
                .cardStyle()

                // Security
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "SECURITY", icon: "lock.shield")

                    Toggle(isOn: $auth.isEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: auth.biometryIcon)
                                .font(.system(size: 18))
                                .foregroundStyle(.portalBlue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lock with \(auth.biometryLabel)")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.textPrimary)
                                Text("Require authentication on launch")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.textDim)
                            }
                        }
                    }
                    .tint(.portalGreen)
                    .onChange(of: auth.isEnabled) { _, enabled in
                        Haptic.tap()
                        if enabled {
                            // Verify biometrics work before fully enabling
                            auth.authenticate()
                        }
                    }
                }
                .cardStyle()

                // About
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "ABOUT", icon: "info.circle")

                    HStack {
                        Text("App")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.textDim)
                        Spacer()
                        Text("Unified Dashboard")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.textPrimary)
                    }
                    Divider().overlay(Color.cardBorder)
                    HStack {
                        Text("Version")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.textDim)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.textPrimary)
                    }
                    Divider().overlay(Color.cardBorder)
                    HStack {
                        Text("Status")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.textDim)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(settings.isConfigured ? .portalGreen : .portalRed)
                                .frame(width: 6, height: 6)
                            Text(settings.isConfigured ? "Configured" : "Not Set")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(settings.isConfigured ? .portalGreen : .portalRed)
                        }
                    }
                    Divider().overlay(Color.cardBorder)
                    HStack {
                        Text("Server")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.textDim)
                        Spacer()
                        Text(settings.serverURL.isEmpty ? "—" : settings.serverURL)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.textDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .cardStyle()
            }
            .padding()
        }
        .background(Color.portalBg)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Test

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let client = APIClient(settings: settings)
        do {
            let overview = try await client.fetchOverview()
            let botCount = overview.bots.count
            await MainActor.run {
                testResult = "Connected — \(botCount) bot\(botCount == 1 ? "" : "s") found"
                testSuccess = true
                isTesting = false
                Haptic.success()
            }
        } catch {
            await MainActor.run {
                testResult = error.localizedDescription
                testSuccess = false
                isTesting = false
                Haptic.error()
            }
        }
    }
}

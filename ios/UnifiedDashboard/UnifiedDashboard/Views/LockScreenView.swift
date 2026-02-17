import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        ZStack {
            Color.portalBg.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.portalBlue.opacity(0.15), .clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 70
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: auth.biometryIcon)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.portalBlue)
                        .shadow(color: .portalBlue.opacity(0.3), radius: 10, x: 0, y: 4)
                }

                VStack(spacing: 8) {
                    Text("Locked")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(.textPrimary)

                    Text("Authenticate to access\nyour trading dashboard")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Spacer()

                // Unlock button
                Button {
                    Haptic.tap()
                    auth.authenticate()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: auth.biometryIcon)
                            .font(.system(size: 18))
                        Text("Unlock with \(auth.biometryLabel)")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.portalBlue, .portalBlue.opacity(0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Auto-trigger auth when the lock screen appears
            auth.authenticate()
        }
    }
}

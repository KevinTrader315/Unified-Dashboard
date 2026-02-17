import Foundation
import LocalAuthentication

@MainActor
class AuthManager: ObservableObject {
    private static let enabledKey = "biometricAuthEnabled"

    /// Whether biometric lock is turned on by the user.
    @Published var isEnabled: Bool {
        didSet { KeychainHelper.save(isEnabled ? "1" : "0", for: Self.enabledKey) }
    }

    /// Whether the app is currently locked (needs auth to proceed).
    @Published var isLocked = false

    /// Human-readable label for the biometry type ("Face ID", "Touch ID", or "Passcode").
    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:    return "Face ID"
        case .touchID:   return "Touch ID"
        case .opticID:   return "Optic ID"
        @unknown default: return "Passcode"
        }
    }

    /// SF Symbol matching the current biometry type.
    var biometryIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:    return "faceid"
        case .touchID:   return "touchid"
        case .opticID:   return "opticid"
        @unknown default: return "lock.fill"
        }
    }

    init() {
        let stored = KeychainHelper.load(for: Self.enabledKey)
        self.isEnabled = stored == "1"
        // Lock immediately if enabled
        if self.isEnabled {
            self.isLocked = true
        }
    }

    /// Prompt the user with biometrics (or device passcode fallback).
    func authenticate() {
        let context = LAContext()
        var error: NSError?

        let policy: LAPolicy = .deviceOwnerAuthentication  // biometrics + passcode fallback

        guard context.canEvaluatePolicy(policy, error: &error) else {
            // Device doesn't support any auth — just unlock
            isLocked = false
            return
        }

        context.evaluatePolicy(
            policy,
            localizedReason: "Unlock to view your trading dashboard"
        ) { success, _ in
            DispatchQueue.main.async {
                if success {
                    self.isLocked = false
                }
            }
        }
    }

    /// Called when the app moves to the background — re-lock if enabled.
    func lock() {
        if isEnabled {
            isLocked = true
        }
    }
}

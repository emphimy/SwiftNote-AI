import Foundation
import LocalAuthentication

enum BiometricType {
    case none
    case touchID
    case faceID
    
    var description: String {
        switch self {
        case .none:
            return "None"
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        }
    }
}

class BiometricAuthManager {
    static let shared = BiometricAuthManager()
    
    private init() {}
    
    // Check what type of biometric authentication is available
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        if #available(iOS 11.0, *) {
            switch context.biometryType {
            case .touchID:
                return .touchID
            case .faceID:
                return .faceID
            default:
                return .none
            }
        } else {
            return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) ? .touchID : .none
        }
    }
    
    // Authenticate using biometrics
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                throw error
            }
            return false
        }
        
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            throw error
        }
    }
    
    // Check if app is locked with biometrics
    func isAppLocked() -> Bool {
        return UserDefaults.standard.bool(forKey: "biometricLockEnabled")
    }
    
    // Set app lock state
    func setAppLock(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "biometricLockEnabled")
    }
}

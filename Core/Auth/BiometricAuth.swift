// Rosemount — BiometricAuth.swift
// Face ID / Touch ID authentication using LocalAuthentication.
// Swift 5.10 | iOS 17.0+

import Foundation
import LocalAuthentication

// MARK: - BiometricType

enum BiometricType {
    case faceID
    case touchID
    case none
}

// MARK: - BiometricError

enum BiometricError: Error, LocalizedError {
    case notAvailable
    case notEnrolled
    case authenticationFailed
    case userCancelled
    case lockout

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device."
        case .notEnrolled:
            return "No biometric credentials are enrolled. Please set up Face ID or Touch ID in Settings."
        case .authenticationFailed:
            return "Biometric authentication failed. Please try again."
        case .userCancelled:
            return "Authentication was cancelled by the user."
        case .lockout:
            return "Biometric authentication is locked out due to too many failed attempts. Please use your device passcode."
        }
    }
}

// MARK: - BiometricAuth

/// Actor-isolated biometric authentication service.
/// Uses `LocalAuthentication` to evaluate Face ID / Touch ID policy.
actor BiometricAuth {

    // MARK: - Private State

    private let context: LAContext

    // MARK: - Init

    init() {
        self.context = LAContext()
    }

    // MARK: - Public API

    /// Returns the type of biometry available on this device.
    /// Calls `canEvaluatePolicy` internally to populate `biometryType`.
    var biometricType: BiometricType {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch ctx.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            // visionOS optic ID — treat as none on iOS
            return .none
        @unknown default:
            return .none
        }
    }

    /// Returns `true` when the device has usable biometric hardware and enrolled credentials.
    func isBiometricAvailable() -> Bool {
        let ctx = LAContext()
        var error: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Presents the system biometric prompt with the supplied `reason` string.
    ///
    /// - Parameter reason: A localised string shown to the user explaining why authentication is requested.
    /// - Returns: `true` when the user successfully authenticates.
    /// - Throws: `BiometricError` describing the failure.
    func authenticate(reason: String) async throws -> Bool {
        // Create a fresh context for every authentication attempt so that
        // invalidated contexts from previous calls do not interfere.
        let ctx = LAContext()
        var policyError: NSError?

        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            throw mapPolicyError(policyError)
        }

        do {
            let success = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let laError as LAError {
            throw mapLAError(laError)
        } catch {
            throw BiometricError.authenticationFailed
        }
    }

    // MARK: - Private Helpers

    private func mapPolicyError(_ error: NSError?) -> BiometricError {
        guard let error else { return .notAvailable }
        switch LAError.Code(rawValue: error.code) {
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryLockout:
            return .lockout
        default:
            return .notAvailable
        }
    }

    private func mapLAError(_ error: LAError) -> BiometricError {
        switch error.code {
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel, .appCancel, .systemCancel:
            return .userCancelled
        case .userFallback:
            // User tapped the fallback button (passcode); treat as cancelled
            // from the biometric perspective.
            return .userCancelled
        case .biometryLockout:
            return .lockout
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .passcodeNotSet:
            return .notAvailable
        default:
            return .authenticationFailed
        }
    }
}

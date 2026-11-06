// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import LocalAuthentication

// MARK: - Approval gate (Touch ID / Face ID)

/// Abstraksi approval supaya alur klaim/eksekusi/recovery di
/// `RequestProcessor` dapat diuji dengan test double (lihat
/// `IntegrationSelfTest.swift`) tanpa memicu dialog Touch ID/Face ID asli.
/// `ApprovalGate` di bawah adalah satu-satunya implementasi yang dipakai
/// gateway sungguhan.
protocol ApprovalGating {
    func approve(reason: String) -> Bool
}

final class ApprovalGate: ApprovalGating {
    /// Blocks until the operator approves/denies via Touch ID/Face ID,
    /// or until biometric auth is unavailable (falls back to device password
    /// via LAContext's own fallback UI).
    func approve(reason: String) -> Bool {
        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            let message = policyError?.localizedDescription ?? "unknown"
            FileHandle.standardError.write("Approval tidak tersedia di perangkat ini: \(message)\n".data(using: .utf8)!)
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        var approved = false

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
            approved = success
            if let evalError {
                FileHandle.standardError.write("Approval gagal/dibatalkan: \(evalError.localizedDescription)\n".data(using: .utf8)!)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return approved
    }
}

// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Security
import LocalAuthentication

enum DoctorKeychainResult {
    case available, failed, uncertain
}

func doctorKeychainResult(_ status: OSStatus) -> DoctorKeychainResult {
    switch status {
    case errSecSuccess: return .available
    case errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed: return .uncertain
    default: return .failed
    }
}

struct DoctorCheck {
    let name: String
    let valid: Bool
    let detail: String
}

func doctorDirectoryAccessible(_ url: URL) -> Bool {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        && fm.isReadableFile(atPath: url.path) && fm.isWritableFile(atPath: url.path)
        && fm.isExecutableFile(atPath: url.path)
}

func doctorChecks(environment: [String: String], base: URL, sshExecutable: URL,
                  directoryAccessible: (URL) -> Bool = doctorDirectoryAccessible,
                  executable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
                  keychainStatus: () -> OSStatus) -> [DoctorCheck] {
    var checks: [DoctorCheck] = []
    func report(_ name: String, _ valid: Bool, _ detail: String) {
        checks.append(DoctorCheck(name: name, valid: valid, detail: detail))
    }
    for key in ["GATEWAY_POLL_INTERVAL_SECONDS", "GATEWAY_SSH_TIMEOUT_SECONDS", "GATEWAY_IDLE_HEARTBEAT_SECONDS"] {
        if let value = environment[key] {
            let number = TimeInterval(value)
            report(key, number.map { $0.isFinite && (key == "GATEWAY_IDLE_HEARTBEAT_SECONDS" ? $0 >= 0 : $0 > 0) } ?? false, "Periksa nilai interval dalam detik.")
        }
    }
    if let value = environment["GATEWAY_AUDIT_LOG_MAX_BYTES"] {
        report("GATEWAY_AUDIT_LOG_MAX_BYTES", UInt64(value).map { $0 > 0 } ?? false, "Gunakan bilangan bulat positif.")
    }
    for key in ["GATEWAY_SSH_HOST", "GATEWAY_BASE_DIR_NAME", "GATEWAY_KEYCHAIN_SERVICE_NAME"] {
        if let value = environment[key] { report(key, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Nilai tidak boleh kosong.") }
    }
    if checks.allSatisfy(\.valid) { report("Konfigurasi", true, "nilai environment valid atau menggunakan default") }
    for url in [base] + ["requests", "processing", "responses", "processed"].map({ base.appendingPathComponent($0, isDirectory: true) }) {
        let accessible = directoryAccessible(url)
        report("Direktori \(url.path)", accessible, accessible ? "akses metadata tersedia" : "tidak ada atau tidak dapat diakses; periksa direktori dan izinnya")
    }
    report("SSH", executable(sshExecutable.path), "Periksa /usr/bin/ssh; koneksi remote tidak diuji.")
    switch doctorKeychainResult(keychainStatus()) {
    case .available: report("Keychain", true, "metadata tersedia tanpa interaksi; akses secret tidak diuji")
    case .uncertain: report("Keychain", false, "tidak dapat dipastikan tanpa item atau interaksi; periksa Keychain secara manual")
    case .failed: report("Keychain", false, "pemeriksaan metadata gagal; periksa akses Keychain")
    }
    return checks
}

func runDoctor() -> Bool {
    let checks = doctorChecks(environment: ProcessInfo.processInfo.environment,
                              base: GatewayConfig.defaultBaseDirURL(),
                              sshExecutable: URL(fileURLWithPath: "/usr/bin/ssh")) {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(GatewayConfig.configuredKeychainServiceName).bundle.\(SecretStore.defaultBundle)",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var metadata: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &metadata)
    }
    for check in checks { print("\(check.valid ? "OK" : "MASALAH"): \(check.name) — \(check.detail)") }
    print("Hasil adalah snapshot; akses aktual dapat berubah dan tidak menjamin operasi berhasil.")
    return checks.allSatisfy(\.valid)
}

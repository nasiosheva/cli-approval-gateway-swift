// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Security

func runDoctorSelfTest() -> Bool {
    var failures = 0
    func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("[selftest] GAGAL: \(message)")
        }
    }
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("gateway-doctor-selftest-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: base) }
    let ssh = URL(fileURLWithPath: "/usr/bin/ssh")
    func checks(_ environment: [String: String] = [:], status: OSStatus = errSecSuccess,
                directoryAccessible: (URL) -> Bool = doctorDirectoryAccessible,
                executable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> [DoctorCheck] {
        doctorChecks(environment: environment, base: base, sshExecutable: ssh,
                     directoryAccessible: directoryAccessible, executable: executable, keychainStatus: { status })
    }
    let missing = checks()
    check(missing.contains { $0.name.hasPrefix("Direktori ") && !$0.valid }, "direktori yang tidak ada harus gagal")
    check(!fm.fileExists(atPath: base.path), "doctor tidak boleh membuat direktori")
    do {
        for path in ["", "requests", "processing", "responses", "processed"] {
            try fm.createDirectory(at: base.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        check(checks(executable: { _ in true }).allSatisfy(\.valid), "konfigurasi dan direktori sehat harus berhasil")
        let inaccessible = checks(directoryAccessible: { $0.lastPathComponent != "responses" }, executable: { _ in true })
        check(inaccessible.contains { $0.name.hasSuffix("responses") && !$0.valid }, "direktori tidak dapat diakses harus gagal")
        check(checks(executable: { _ in false }).contains { $0.name == "SSH" && !$0.valid }, "SSH yang tidak tersedia harus gagal")
        for (key, value) in [("GATEWAY_POLL_INTERVAL_SECONDS", "0"), ("GATEWAY_SSH_TIMEOUT_SECONDS", "nan"), ("GATEWAY_IDLE_HEARTBEAT_SECONDS", "-1"), ("GATEWAY_AUDIT_LOG_MAX_BYTES", "0"), ("GATEWAY_SSH_HOST", " "), ("GATEWAY_BASE_DIR_NAME", ""), ("GATEWAY_KEYCHAIN_SERVICE_NAME", " ")] {
            check(checks([key: value], executable: { _ in true }).contains { $0.name == key && !$0.valid }, "konfigurasi tidak valid \(key) harus gagal")
        }
        check(checks(["GATEWAY_IDLE_HEARTBEAT_SECONDS": "0"], executable: { _ in true }).allSatisfy(\.valid), "heartbeat nol harus valid")
        for status in [errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed] {
            let result = checks(status: status, executable: { _ in true }).first { $0.name == "Keychain" }
            check(result?.valid == false && result?.detail.contains("tidak dapat dipastikan") == true, "Keychain tidak pasti harus dilaporkan")
        }
        let failure = checks(status: errSecParam, executable: { _ in true }).first { $0.name == "Keychain" }
        check(failure?.valid == false && failure?.detail.contains("gagal") == true, "kegagalan Keychain harus dilaporkan")
    } catch {
        check(false, "gagal menyiapkan direktori sementara: \(error)")
    }
    if failures == 0 { print("[selftest] BERHASIL: diagnostik doctor lulus tanpa mengakses secret.") }
    return failures == 0
}

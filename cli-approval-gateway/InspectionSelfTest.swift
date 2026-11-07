// Mories Deo Hutapea,S.E.,S.Kom
import Foundation

func runInspectionSelfTest() -> Bool {
    var failures = 0
    func check(_ value: Bool, _ message: String) {
        if !value { failures += 1; print("[selftest] GAGAL: \(message)") }
    }
    let summary = SessionSummary()
    summary.record(["approved": true, "exitCode": Int32(0)])
    summary.record(["approved": true, "exitCode": Int32(1)])
    summary.record(["approved": false, "exitCode": NSNull()])
    summary.record(["approved": false, "exitCode": NSNull(), "status": "host-unknown"])
    summary.record(["approved": true, "exitCode": NSNull()])
    check(summary.succeeded == 1 && summary.failed == 3 && summary.rejected == 1, "klasifikasi hasil sesi")
    let empty = SessionSummary()
    check(empty.succeeded == 0 && empty.failed == 0 && empty.rejected == 0, "sesi kosong")
    check(!validHostCheckTarget("-oProxyCommand=x") && !validHostCheckTarget("bad\nhost") && validHostCheckTarget("localhost"), "validasi input host")
    let options = hostCheckArguments("localhost")
    check(options.contains("BatchMode=yes") && options.contains("StrictHostKeyChecking=yes") && options.contains("UpdateHostKeys=no") && options.suffix(2).elementsEqual(["localhost", "true"]), "opsi SSH noninteraktif dan known_hosts")
    let success = runHostCheckProcess(executable: "/bin/sh", arguments: ["-c", "printf ok"], timeout: 2)
    check(success.exitCode == 0 && success.stderr == "ok", "proses sukses")
    let failure = runHostCheckProcess(executable: "/bin/sh", arguments: ["-c", "printf gagal >&2; exit 7"], timeout: 2)
    check(failure.exitCode == 7 && failure.stderr == "gagal", "proses gagal")
    let start = Date()
    let timeout = runHostCheckProcess(executable: "/bin/sh", arguments: ["-c", "sleep 10 & wait"], timeout: 0.25)
    check(timeout.timedOut && Date().timeIntervalSince(start) < 2, "timeout menghentikan grup proses")
    let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-host-check-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        let known = testDir.appendingPathComponent("known_hosts")
        try "# selftest\n".write(to: known, atomically: true, encoding: .utf8)
        let original = try Data(contentsOf: known)
        let args = ["-F", "/dev/null", "-o", "UserKnownHostsFile=\(known.path)", "-p", "1"] + hostCheckArguments("127.0.0.1")
        let isolated = runHostCheckProcess(executable: "/usr/bin/ssh", arguments: args, timeout: 2)
        check(isolated.exitCode != 0 && !isolated.stderr.lowercased().contains("password:"), "koneksi terisolasi gagal tanpa prompt")
        check((try? Data(contentsOf: known)) == original, "known_hosts tidak berubah")
    } catch { check(false, "menyiapkan pemeriksaan SSH terisolasi: \(error)") }
    if failures == 0 { print("[selftest] BERHASIL: pemeriksaan host dan ringkasan sesi.") }
    return failures == 0
}

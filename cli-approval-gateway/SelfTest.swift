// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Self-test: drain stdout/stderr tanpa deadlock
//
// Proyek ini belum punya target XCTest, jadi stress test untuk
// `runProcessCapturingOutput` disediakan sebagai subcommand CLI yang bisa
// dijalankan manual atau dari CI: `cli-approval-gateway selftest ssh-drain`.
// Test ini menjalankan subprocess yang menulis lebih dari kapasitas pipe
// (umumnya 64KB di macOS) ke stdout DAN stderr, dengan timeout eksplisit
// supaya deadlock terdeteksi sebagai kegagalan test, bukan hang selamanya.

private let selfTestBytesPerStream = 4 * 1024 * 1024 // 4MB, jauh di atas kapasitas pipe tipikal
private let selfTestTimeoutSeconds: TimeInterval = 15

func runSSHDrainSelfTest() -> Bool {
    print("[selftest] Menjalankan subprocess yang menulis \(selfTestBytesPerStream) byte ke stdout dan \(selfTestBytesPerStream) byte ke stderr...")

    let script = "head -c \(selfTestBytesPerStream) /dev/zero; head -c \(selfTestBytesPerStream) /dev/zero 1>&2; exit 7"

    var result: CommandResult?
    let semaphore = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .userInitiated).async {
        result = runProcessCapturingOutput(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            stdinData: nil
        )
        semaphore.signal()
    }

    let outcome = semaphore.wait(timeout: .now() + selfTestTimeoutSeconds)

    guard outcome == .success else {
        print("[selftest] GAGAL: subprocess tidak selesai dalam \(selfTestTimeoutSeconds)s — kemungkinan deadlock pada pembacaan stdout/stderr.")
        return false
    }

    guard let result else {
        print("[selftest] GAGAL: tidak ada hasil dari subprocess.")
        return false
    }

    var ok = true

    if result.exitCode != 7 {
        print("[selftest] GAGAL: exit code \(result.exitCode), diharapkan 7.")
        ok = false
    }

    if result.stdout.utf8.count != selfTestBytesPerStream {
        print("[selftest] GAGAL: stdout berisi \(result.stdout.utf8.count) byte, diharapkan \(selfTestBytesPerStream).")
        ok = false
    }

    if result.stderr.utf8.count != selfTestBytesPerStream {
        print("[selftest] GAGAL: stderr berisi \(result.stderr.utf8.count) byte, diharapkan \(selfTestBytesPerStream).")
        ok = false
    }

    if ok {
        print("[selftest] BERHASIL: exit_code=7, stdout dan stderr masing-masing \(selfTestBytesPerStream) byte diterima utuh tanpa deadlock.")
    }

    return ok
}

func runSelfTestSubcommand(_ args: [String]) -> Never {
    guard let name = args.first else {
        FileHandle.standardError.write("Penggunaan: cli-approval-gateway selftest ssh-drain\n".data(using: .utf8)!)
        exit(2)
    }

    switch name {
    case "ssh-drain":
        exit(runSSHDrainSelfTest() ? 0 : 1)
    default:
        FileHandle.standardError.write("Self-test tidak dikenal: \(name)\n".data(using: .utf8)!)
        exit(2)
    }
}

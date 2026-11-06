// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Darwin

// MARK: - Remote execution over SSH

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Abstraksi eksekusi command supaya alur klaim/eksekusi/recovery di
/// `RequestProcessor` dapat diuji dengan test double (lihat
/// `IntegrationSelfTest.swift`) tanpa membuka koneksi SSH asli.
/// `SSHExecutor` di bawah adalah satu-satunya implementasi yang dipakai
/// gateway sungguhan.
protocol CommandExecuting {
    func run(host: String, script: String) -> CommandResult
}

final class SSHExecutor: CommandExecuting {
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = GatewayConfig.defaultSSHTimeoutSeconds) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Mengirim isi script (sudah diresolve) sebagai stdin ke
    /// `ssh <host> bash -s`, bukan menulis file ke remote — host, auth, dan
    /// credential server tetap dikendalikan sepenuhnya oleh konfigurasi
    /// SSH/server, tidak ada yang lewat proses ini selain lewat stdin pipe
    /// yang langsung ditutup setelah terkirim. `host` diteruskan per
    /// panggilan (bukan disimpan di init) supaya satu executor bisa
    /// melayani banyak server berbeda dalam proses gateway yang sama.
    func run(host: String, script: String) -> CommandResult {
        runProcessCapturingOutput(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: [host, "bash", "-s"],
            stdinData: script.data(using: .utf8),
            timeoutSeconds: timeoutSeconds
        )
    }
}

/// Jalankan subprocess, kirim `stdinData` lalu tutup stdin, dan kuras stdout
/// serta stderr SECARA BERSAMAAN di thread terpisah sampai masing-masing
/// mencapai EOF, baru menunggu proses selesai. Membaca satu stream sampai
/// EOF sebelum memulai stream lain dapat deadlock begitu command menulis
/// lebih dari kapasitas buffer pipe (umumnya 64KB di macOS) ke stream yang
/// belum dibaca, karena penulis di sisi lain blok menunggu pembaca.
func runProcessCapturingOutput(executableURL: URL, arguments: [String], stdinData: Data?, timeoutSeconds: TimeInterval? = nil) -> CommandResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    let processExited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in processExited.signal() }

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        return CommandResult(exitCode: -1, stdout: "", stderr: "Gagal menjalankan \(executableURL.path): \(error.localizedDescription)")
    }

    var stdoutData = Data()
    var stderrData = Data()
    let group = DispatchGroup()

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }

    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }

    if let stdinData {
        DispatchQueue.global(qos: .userInitiated).async {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
            stdinPipe.fileHandleForWriting.closeFile()
        }
    } else {
        stdinPipe.fileHandleForWriting.closeFile()
    }

    var timedOut = false
    if let timeoutSeconds, processExited.wait(timeout: .now() + timeoutSeconds) == .timedOut {
        if process.isRunning {
            timedOut = true
            process.terminate()
            if processExited.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                processExited.wait()
            }
        }
    }

    // Tunggu kedua pembaca mencapai EOF setelah proses ditutup.
    group.wait()
    process.waitUntilExit()

    return CommandResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? "",
        timedOut: timedOut
    )
}

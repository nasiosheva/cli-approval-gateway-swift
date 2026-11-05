// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Remote execution over SSH

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

final class SSHExecutor {
    /// Mengirim isi script (sudah diresolve) sebagai stdin ke
    /// `ssh <host> bash -s`, bukan menulis file ke remote — host, auth, dan
    /// credential server tetap dikendalikan sepenuhnya oleh konfigurasi
    /// SSH/server, tidak ada yang lewat proses ini selain lewat stdin pipe
    /// yang langsung ditutup setelah terkirim. `host` diteruskan per
    /// panggilan (bukan disimpan di init) supaya satu executor bisa
    /// melayani banyak server berbeda dalam proses gateway yang sama.
    func run(host: String, script: String) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [host, "bash", "-s"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: "Gagal menjalankan ssh: \(error.localizedDescription)")
        }

        if let data = script.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}

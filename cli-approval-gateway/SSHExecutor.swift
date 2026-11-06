// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Remote execution over SSH

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
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
            stdinData: script.data(using: .utf8)
        )
    }
}

/// Jalankan subprocess, kirim `stdinData` lalu tutup stdin, dan kuras stdout
/// serta stderr SECARA BERSAMAAN di thread terpisah sampai masing-masing
/// mencapai EOF, baru menunggu proses selesai. Membaca satu stream sampai
/// EOF sebelum memulai stream lain dapat deadlock begitu command menulis
/// lebih dari kapasitas buffer pipe (umumnya 64KB di macOS) ke stream yang
/// belum dibaca, karena penulis di sisi lain blok menunggu pembaca.
func runProcessCapturingOutput(executableURL: URL, arguments: [String], stdinData: Data?) -> CommandResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

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

    if let stdinData {
        stdinPipe.fileHandleForWriting.write(stdinData)
    }
    stdinPipe.fileHandleForWriting.closeFile()

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

    // Tunggu kedua pembaca mencapai EOF (artinya kedua ujung penulis pipe
    // sudah ditutup oleh OS saat proses keluar) sebelum menunggu proses,
    // supaya kedua stream selalu terkuras penuh tanpa bergantung urutan.
    group.wait()
    process.waitUntilExit()

    return CommandResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}

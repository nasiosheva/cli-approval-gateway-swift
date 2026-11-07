// Mories Deo Hutapea,S.E.,S.Kom

//
//  main.swift
//  cli-approval-gateway
//
//  Created by Mories Hutapea on 05/11/26.
//
//  Daemon lokal: watch folder `requests/` untuk file `<id>.sh` berisi
//  command yang diminta agent (Claude atau agent lain), minta approval
//  Touch ID/Face ID ke operator, baru eksekusi via SSH ke server target,
//  lalu tulis hasilnya ke `responses/<id>.json`.
//
//  Password (sudo, DB, dll) disimpan per-tag di macOS Keychain lewat
//  subcommand `pw add/list/remove`, dilindungi Touch ID/Face ID saat
//  diambil. Command di file request bisa memuat placeholder `{{pw:tag}}`
//  yang disubstitusi dengan nilai asli hanya tepat sebelum dikirim ke SSH
//  stdin — isi mentah (dengan placeholder, bukan nilai asli) yang
//  ditampilkan ke terminal dan ditulis ke audit log, supaya password tidak
//  pernah tersimpan/tercetak dalam bentuk plaintext di luar Keychain.

import Foundation
import Darwin

var savedTerminalSettings = termios()
var terminalSettingsActive = false

func restoreTerminal() {
    if terminalSettingsActive {
        tcsetattr(STDIN_FILENO, TCSANOW, &savedTerminalSettings)
        terminalSettingsActive = false
    }
}

func waitForStopKey(seconds: TimeInterval) -> Bool {
    guard isatty(STDIN_FILENO) == 1, tcgetattr(STDIN_FILENO, &savedTerminalSettings) == 0 else {
        Thread.sleep(forTimeInterval: seconds)
        return false
    }
    var settings = savedTerminalSettings
    settings.c_lflag &= ~tcflag_t(ICANON | ECHO)
    guard tcsetattr(STDIN_FILENO, TCSANOW, &settings) == 0 else {
        Thread.sleep(forTimeInterval: seconds)
        return false
    }
    terminalSettingsActive = true
    defer { restoreTerminal() }
    let deadline = Date().addingTimeInterval(seconds)
    while deadline.timeIntervalSinceNow > 0 {
        let remaining = deadline.timeIntervalSinceNow
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, Double(Int32.max))))
        if ready <= 0 { break }
        var character: UInt8 = 0
        if read(STDIN_FILENO, &character, 1) == 1 && character == 115 { return true }
    }
    return false
}

// MARK: - Entry point

func printTopLevelHelp() {
    print("""
    cli-approval-gateway — daemon lokal yang menjalankan command di server
    lewat SSH setelah disetujui operator via Touch ID/Face ID.

    PEMAKAIAN UNTUK AGENT (Claude Code atau agent lain) MEMBUAT REQUEST:
      1. Operator harus sudah menjalankan watcher (`cli-approval-gateway`
         tanpa argumen) di satu terminal dan membiarkannya berjalan.
      2. Tulis script command ke file SEMENTARA di folder `requests/`
         (nama bebas), lalu RENAME ke `<id>.sh` dengan ID unik — JANGAN
         langsung menulis nama `.sh` final, supaya watcher tidak membaca
         file yang belum selesai ditulis. Baris pertama file boleh berupa
         `#GATEWAY-HOST: <host>` untuk override host SSH default.
      3. Tunggu lalu baca `responses/<id>.json`. Field: id, timestamp,
         host, approved, exitCode, stdout, stderr, dan kadang `status`
         tambahan (lihat di bawah). `approved: true` BUKAN berarti
         command berhasil — selalu cek juga `exitCode`.
      4. Untuk password di command, pakai placeholder `{{pw:tag}}` —
         JANGAN PERNAH menaruh password asli di command. Gateway resolve
         `{{pw:tag}}` ke bundle password milik host request itu dulu,
         baru fallback ke bundle 'default' kalau tag tidak ada di bundle
         host tersebut. Operator yang mengisi bundle via 'pw add'.

      Default folder data: `~/.cli-approval-gateway/` (override lewat
      env `GATEWAY_BASE_DIR_NAME`). Subfolder: `requests/`, `processing/`
      (internal, jangan disentuh manual), `responses/`, `processed/`.

      Nilai `status` tambahan pada response (selain sukses biasa):
      `duplicate-id-rejected`, `recovery-interrupted`, `execution-unknown`,
      `aborted-before-execution`, `timed-out`, `host-unknown` — semuanya berarti command TIDAK
      dijalankan ulang otomatis; kirim request baru dengan ID BARU kalau
      masih perlu, jangan pakai ID yang sama.
      Saat `timed-out`, hasil remote mungkin tidak diketahui; periksa server
      sebelum mencoba ulang.

    SUBCOMMAND:
      cli-approval-gateway                 Jalankan watcher (loop utama, perlu operator jaga terminal)
      cli-approval-gateway pw <aksi> ...    Kelola password Keychain (jalankan 'pw' tanpa argumen untuk detail)
      cli-approval-gateway selftest <nama>  Self-test ('ssh-drain', 'ssh-timeout', 'lifecycle', 'operability', 'doctor', 'inspection') tanpa SSH/Touch ID asli
      cli-approval-gateway cleanup --older-than <hari> [--dry-run]  Hapus pasangan response/request lama
      cli-approval-gateway doctor           Periksa kesiapan lokal tanpa mengubah data
      cli-approval-gateway status <id>      Periksa status request tanpa mengubah data
      cli-approval-gateway audit search [--host <host>] [--date <YYYY-MM-DD>] [--approved <true|false>]  Cari audit
      cli-approval-gateway host check <host>  Periksa koneksi SSH noninteraktif
      cli-approval-gateway clear-responses [--yes]  Hapus semua file response JSON
      cli-approval-gateway clear-audit [--yes]      Kosongkan audit log
      cli-approval-gateway --help | -h      Tampilkan bantuan ini

      Saat watcher berjalan, tekan s untuk berhenti dan melihat ringkasan sesi.
      Ringkasan hanya mencakup hasil sesi ini, bukan recovery atau audit permanen.
      Host check mengautentikasi SSH dan menjalankan `true` di remote; konfigurasi
      SSH, termasuk proxy atau forced command, dapat memengaruhi perilakunya.
      Doctor dapat berjalan saat watcher aktif; hasilnya snapshot metadata,
      tidak menguji koneksi SSH atau akses secret. Masalah atau hasil yang
      tidak dapat dipastikan menghasilkan exit code bukan nol.
      Penghapusan memerlukan konfirmasi terminal atau --yes untuk otomasi,
      dan tetap memerlukan lock watcher.

      Argumen pertama selain di atas (termasuk typo) ditolak dengan error
      ke stderr dan exit code 2 — TIDAK akan diam-diam menjalankan watcher.

    ENV VAR (opsional, untuk override saat start watcher):
      GATEWAY_SSH_HOST                Host SSH default (fallback: pe-server)
      GATEWAY_BASE_DIR_NAME           Nama folder data di bawah home (fallback: .cli-approval-gateway)
      GATEWAY_POLL_INTERVAL_SECONDS   Interval polling requests/ dalam detik (fallback: 1.0)
      GATEWAY_SSH_TIMEOUT_SECONDS     Batas waktu SSH per request dalam detik (fallback: 120)
      GATEWAY_AUDIT_LOG_MAX_BYTES     Ukuran maksimum audit.log dalam byte (fallback: 10485760)
      GATEWAY_IDLE_HEARTBEAT_SECONDS  Interval heartbeat idle dalam detik (fallback: 300; 0 untuk mematikan)
      GATEWAY_KEYCHAIN_SERVICE_NAME   Nama service Keychain untuk 'pw' (fallback: com.cli-approval-gateway.secrets)

    PERINGATAN KEAMANAN UNTUK AGENT: JANGAN PERNAH menjalankan
    `cli-approval-gateway pw reveal <tag> --host <host>` atau
    `pw list`/`pw show` secara otomatis — output-nya bisa memuat atau
    mengindikasikan data sensitif. Perintah 'pw' (selain untuk membuat tag
    lewat 'add') hanya untuk dijalankan langsung oleh operator manusia di
    terminalnya sendiri. Jalankan 'cli-approval-gateway pw' tanpa argumen
    untuk detail lengkap tiap aksi 'pw' (termasuk 'migrate-bundles').
    """)
}

let secretStore = SecretStore(
    baseService: GatewayConfig.configuredKeychainServiceName,
    registryURL: GatewayConfig.defaultBaseDirURL().appendingPathComponent("secret-bundles.json")
)
let gate = ApprovalGate()
let arguments = CommandLine.arguments

if arguments.count > 1, ["--help", "-h", "help"].contains(arguments[1]) {
    printTopLevelHelp()
    exit(0)
}

if arguments.count > 1, arguments[1] == "pw" {
    runPasswordSubcommand(Array(arguments.dropFirst(2)), store: secretStore, gate: gate)
}

if arguments.count > 1, arguments[1] == "selftest" {
    runSelfTestSubcommand(Array(arguments.dropFirst(2)))
}

if arguments.count > 1, arguments[1] == "doctor" {
    guard arguments.count == 2 else {
        FileHandle.standardError.write("Doctor tidak menerima argumen tambahan.\n".data(using: .utf8)!)
        exit(2)
    }
    exit(runDoctor() ? 0 : 1)
}

if arguments.count > 1, arguments[1] == "status" {
    runRequestStatusSubcommand(Array(arguments.dropFirst(2)))
}

if arguments.count > 1, arguments[1] == "audit" { runAuditSearch(Array(arguments.dropFirst(2))) }
if arguments.count > 1, arguments[1] == "host" { runHostCheck(Array(arguments.dropFirst(2))) }

let knownSubcommands = ["pw", "selftest", "doctor", "status", "audit", "host", "cleanup", "clear-responses", "clear-audit", "--help", "-h", "help"]
if arguments.count > 1, !knownSubcommands.contains(arguments[1]) {
    FileHandle.standardError.write("Argumen tidak dikenal: '\(arguments[1])'\nJalankan 'cli-approval-gateway --help' untuk daftar subcommand yang valid, atau tanpa argumen untuk start watcher.\n".data(using: .utf8)!)
    exit(2)
}

let isClear = arguments.count > 1 && ["clear-responses", "clear-audit"].contains(arguments[1])
if isClear && !(arguments.count == 2 || (arguments.count == 3 && arguments[2] == "--yes")) {
    FileHandle.standardError.write("Penggunaan: \(arguments[1]) [--yes]\n".data(using: .utf8)!)
    exit(2)
}
if isClear && arguments.count == 2 && isatty(STDIN_FILENO) != 1 {
    FileHandle.standardError.write("Konfirmasi membutuhkan terminal interaktif; gunakan --yes untuk otomasi.\n".data(using: .utf8)!)
    exit(1)
}

let config = GatewayConfig.load()

// Lock harus diambil sebelum apa pun lain (termasuk recovery) supaya dua
// instance yang start bersamaan terhadap base dir yang sama tidak bisa
// berdua-dua masuk ke loop/recovery. fd sengaja TIDAK ditutup — lock
// terikat ke file descriptor ini dan harus tetap terbuka sepanjang hidup
// proses; ditutup otomatis oleh OS saat proses berhenti.
do {
    _ = try acquireSingleInstanceLock(at: config.lockFileURL)
} catch {
    FileHandle.standardError.write("Gagal start: \(error)\nAda instance gateway lain yang sudah berjalan untuk \(config.baseDir.path). Hentikan instance itu dulu (lihat 'ps aux | grep cli-approval-gateway') sebelum menjalankan yang baru.\n".data(using: .utf8)!)
    exit(1)
}

if isClear {
    if arguments.count == 2 {
        let target = arguments[1] == "clear-responses" ? config.responsesDir.path : config.auditLogURL.path
        print("Hapus data di \(target)? [y/N] ", terminator: "")
        fflush(stdout)
        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard answer == "y" || answer == "yes" else {
            print("Penghapusan dibatalkan.")
            exit(1)
        }
    }
    do {
        let fm = FileManager.default
        if arguments[1] == "clear-responses" {
            let files = try fm.contentsOfDirectory(at: config.responsesDir, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                try fm.removeItem(at: file)
            }
            print("Semua response JSON telah dihapus.")
        } else {
            if fm.fileExists(atPath: config.auditLogURL.path) {
                let handle = try FileHandle(forWritingTo: config.auditLogURL)
                defer { try? handle.close() }
                try handle.truncate(atOffset: 0)
            }
            print("Audit log telah dikosongkan.")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("Gagal menghapus data: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if arguments.count > 1, arguments[1] == "cleanup" {
    runCleanupSubcommand(Array(arguments.dropFirst(2)), config: config)
}

let executor = SSHExecutor(timeoutSeconds: config.sshTimeoutSeconds)
let logger = AuditLogger(url: config.auditLogURL, maxBytes: config.auditLogMaxBytes)
let sessionSummary = SessionSummary()

print("cli-approval-gateway berjalan.")
print("Requests folder  : \(config.requestsDir.path)")
print("Processing folder: \(config.processingDir.path)")
print("Responses folder : \(config.responsesDir.path)")
print("Audit log        : \(config.auditLogURL.path)")
print("SSH host default : \(config.sshHost) (override per-request lewat baris pertama '#GATEWAY-HOST: <host>')")
print("Kelola password  : cli-approval-gateway pw add|list|remove <tag> --host <host>  ('default' untuk bundle fallback)")
print("Placeholder      : pakai {{pw:<tag>}} di dalam command untuk substitusi password")
print("Tekan s atau Ctrl-C untuk berhenti.\n")

signal(SIGINT) { _ in
    restoreTerminal()
    exit(130)
}
signal(SIGTERM) { _ in
    restoreTerminal()
    exit(143)
}

print("Memeriksa request yang tertinggal di processing/ dari sesi sebelumnya...")
recoverInterruptedRequests(config: config, logger: logger)

let fm = FileManager.default
var lastHeartbeat = Date()
while true {
    if let files = try? fm.contentsOfDirectory(at: config.requestsDir, includingPropertiesForKeys: nil) {
        let shFiles = files
            .filter { $0.pathExtension == "sh" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for fileURL in shFiles {
            handleCandidateRequest(fileURL: fileURL, config: config, gate: gate, executor: executor, logger: logger, secrets: secretStore, hostValidator: SSHHostValidator(), notifier: { _ = sendApprovalNotification(id: $0, host: $1) }, outcome: { sessionSummary.record($0) })
        }
        if !shFiles.isEmpty {
            lastHeartbeat = Date()
        } else if let heartbeat = idleHeartbeatIfDue(lastHeartbeat: &lastHeartbeat, interval: config.idleHeartbeatSeconds) {
            print(heartbeat)
        }
    }
    if waitForStopKey(seconds: config.pollIntervalSeconds) {
        sessionSummary.printSummary()
        print("Watcher dihentikan.")
        break
    }
}

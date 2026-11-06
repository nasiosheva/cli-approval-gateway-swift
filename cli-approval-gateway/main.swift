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
         JANGAN PERNAH menaruh password asli di command.

      Default folder data: `~/.cli-approval-gateway/` (override lewat
      env `GATEWAY_BASE_DIR_NAME`). Subfolder: `requests/`, `processing/`
      (internal, jangan disentuh manual), `responses/`, `processed/`.

      Nilai `status` tambahan pada response (selain sukses biasa):
      `duplicate-id-rejected`, `recovery-interrupted`, `execution-unknown`,
      `aborted-before-execution` — semuanya berarti command TIDAK
      dijalankan ulang otomatis; kirim request baru dengan ID BARU kalau
      masih perlu, jangan pakai ID yang sama.

    SUBCOMMAND:
      cli-approval-gateway                 Jalankan watcher (loop utama, perlu operator jaga terminal)
      cli-approval-gateway pw <aksi> ...    Kelola password Keychain (jalankan 'pw' tanpa argumen untuk detail)
      cli-approval-gateway selftest <nama>  Self-test ('ssh-drain' atau 'lifecycle'), tidak perlu Touch ID/SSH asli
      cli-approval-gateway --help | -h      Tampilkan bantuan ini

    ENV VAR (opsional, untuk override saat start watcher):
      GATEWAY_SSH_HOST                Host SSH default (fallback: pe-server)
      GATEWAY_BASE_DIR_NAME           Nama folder data di bawah home (fallback: .cli-approval-gateway)
      GATEWAY_POLL_INTERVAL_SECONDS   Interval polling requests/ dalam detik (fallback: 1.0)
      GATEWAY_KEYCHAIN_SERVICE_NAME   Nama service Keychain untuk 'pw' (fallback: com.cli-approval-gateway.secrets)

    PERINGATAN KEAMANAN UNTUK AGENT: JANGAN PERNAH menjalankan
    `cli-approval-gateway pw reveal <tag>` atau `pw list`/`pw show` secara
    otomatis — output-nya bisa memuat atau mengindikasikan data sensitif.
    Perintah 'pw' (selain untuk membuat tag lewat 'add') hanya untuk
    dijalankan langsung oleh operator manusia di terminalnya sendiri.
    """)
}

let secretStore = SecretStore(service: GatewayConfig.configuredKeychainServiceName)
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

let executor = SSHExecutor()
let logger = AuditLogger(url: config.auditLogURL)

print("cli-approval-gateway berjalan.")
print("Requests folder  : \(config.requestsDir.path)")
print("Processing folder: \(config.processingDir.path)")
print("Responses folder : \(config.responsesDir.path)")
print("Audit log        : \(config.auditLogURL.path)")
print("SSH host default : \(config.sshHost) (override per-request lewat baris pertama '#GATEWAY-HOST: <host>')")
print("Kelola password  : cli-approval-gateway pw add|list|remove <tag>  (tag host-scoped: <tag>@<host>)")
print("Placeholder      : pakai {{pw:<tag>}} di dalam command untuk substitusi password")
print("Tekan Ctrl-C untuk berhenti.\n")

print("Memeriksa request yang tertinggal di processing/ dari sesi sebelumnya...")
recoverInterruptedRequests(config: config, logger: logger)

let fm = FileManager.default
while true {
    if let files = try? fm.contentsOfDirectory(at: config.requestsDir, includingPropertiesForKeys: nil) {
        let shFiles = files
            .filter { $0.pathExtension == "sh" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for fileURL in shFiles {
            handleCandidateRequest(fileURL: fileURL, config: config, gate: gate, executor: executor, logger: logger, secrets: secretStore)
        }
    }
    Thread.sleep(forTimeInterval: config.pollIntervalSeconds)
}

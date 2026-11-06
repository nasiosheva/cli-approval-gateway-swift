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

let secretStore = SecretStore(service: GatewayConfig.configuredKeychainServiceName)
let gate = ApprovalGate()
let arguments = CommandLine.arguments

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

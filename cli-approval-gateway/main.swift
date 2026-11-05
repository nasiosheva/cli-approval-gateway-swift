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

let config = GatewayConfig.load()
let executor = SSHExecutor()
let logger = AuditLogger(url: config.auditLogURL)

print("cli-approval-gateway berjalan.")
print("Requests folder : \(config.requestsDir.path)")
print("Responses folder: \(config.responsesDir.path)")
print("Audit log       : \(config.auditLogURL.path)")
print("SSH host default: \(config.sshHost) (override per-request lewat baris pertama '#GATEWAY-HOST: <host>')")
print("Kelola password : cli-approval-gateway pw add|list|remove <tag>  (tag host-scoped: <tag>@<host>)")
print("Placeholder     : pakai {{pw:<tag>}} di dalam command untuk substitusi password")
print("Tekan Ctrl-C untuk berhenti.\n")

let fm = FileManager.default
while true {
    if let files = try? fm.contentsOfDirectory(at: config.requestsDir, includingPropertiesForKeys: nil) {
        let shFiles = files
            .filter { $0.pathExtension == "sh" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for fileURL in shFiles {
            processRequest(fileURL: fileURL, config: config, gate: gate, executor: executor, logger: logger, secrets: secretStore)
        }
    }
    Thread.sleep(forTimeInterval: config.pollIntervalSeconds)
}

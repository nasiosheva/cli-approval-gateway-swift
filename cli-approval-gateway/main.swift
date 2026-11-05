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
import LocalAuthentication
import Security
import Darwin

// MARK: - Configuration

struct GatewayConfig {
    let baseDir: URL
    let requestsDir: URL
    let responsesDir: URL
    let processedDir: URL
    let auditLogURL: URL
    let sshHost: String
    let pollIntervalSeconds: TimeInterval

    static func load() -> GatewayConfig {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".cli-approval-gateway", isDirectory: true)
        let requests = base.appendingPathComponent("requests", isDirectory: true)
        let responses = base.appendingPathComponent("responses", isDirectory: true)
        let processed = base.appendingPathComponent("processed", isDirectory: true)
        let audit = base.appendingPathComponent("audit.log")

        for dir in [base, requests, responses, processed] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let host = ProcessInfo.processInfo.environment["GATEWAY_SSH_HOST"] ?? "pe-server"
        return GatewayConfig(
            baseDir: base,
            requestsDir: requests,
            responsesDir: responses,
            processedDir: processed,
            auditLogURL: audit,
            sshHost: host,
            pollIntervalSeconds: 1.0
        )
    }
}

// MARK: - Audit log

struct AuditEntry: Codable {
    let id: String
    let timestamp: String
    let host: String
    let command: String
    let approved: Bool
    let exitCode: Int32?
}

final class AuditLogger {
    private let url: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(url: URL) {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    func append(_ entry: AuditEntry) {
        guard let data = try? encoder.encode(entry) else { return }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
    }
}

// MARK: - Approval gate (Touch ID / Face ID)

final class ApprovalGate {
    /// Blocks until the operator approves/denies via Touch ID/Face ID,
    /// or until biometric auth is unavailable (falls back to device password
    /// via LAContext's own fallback UI).
    func approve(reason: String) -> Bool {
        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            let message = policyError?.localizedDescription ?? "unknown"
            FileHandle.standardError.write("Approval tidak tersedia di perangkat ini: \(message)\n".data(using: .utf8)!)
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        var approved = false

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
            approved = success
            if let evalError {
                FileHandle.standardError.write("Approval gagal/dibatalkan: \(evalError.localizedDescription)\n".data(using: .utf8)!)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return approved
    }
}

// MARK: - Secret store (macOS Keychain, per tag)

enum SecretStoreError: Error, CustomStringConvertible {
    case osStatus(OSStatus)
    case notFound(String)
    case approvalDenied(String)
    case invalidData

    var description: String {
        switch self {
        case .osStatus(let status):
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "keychain error status \(status)"
        case .notFound(let tag):
            return "Tag '\(tag)' tidak ditemukan di Keychain."
        case .approvalDenied(let tag):
            return "Approval Touch ID/Face ID untuk tag '\(tag)' ditolak/gagal."
        case .invalidData:
            return "Data password tidak valid (bukan UTF-8)."
        }
    }
}

/// Menyimpan password per-tag di macOS Keychain (generic password item),
/// terpisah per tag lewat `kSecAttrAccount`. Pengambilan nilai (`resolve`)
/// dilindungi Touch ID/Face ID oleh access control yang dipasang saat
/// `add`. Tidak ada password yang pernah ditulis ke file/log oleh kelas ini.
final class SecretStore {
    private let service = "com.cli-approval-gateway.secrets"

    private func baseQuery(tag: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let tag {
            query[kSecAttrAccount as String] = tag
        }
        return query
    }

    func add(tag: String, secret: String) throws {
        guard let data = secret.data(using: .utf8) else { throw SecretStoreError.invalidData }

        // add = upsert: hapus entry lama dengan tag yang sama dulu.
        try? remove(tag: tag)

        // Catatan: SecAccessControl(.userPresence) sengaja TIDAK dipakai di
        // sini — itu butuh entitlement keychain-access-groups yang hanya
        // tersedia untuk app yang signed dengan Team ID penuh (gagal dengan
        // ad-hoc signing: "A required entitlement is not present"). Gate
        // Touch ID/Face ID untuk pengambilan tetap dipaksa di level kode
        // lewat `ApprovalGate` sebelum `resolve()` dipanggil (lihat
        // `resolvePlaceholders`/pemanggil), bukan oleh ACL Keychain.
        var query = baseQuery(tag: tag)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }
    }

    func remove(tag: String) throws {
        let query = baseQuery(tag: tag)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.osStatus(status)
        }
    }

    func listTags() throws -> [String] {
        var query = baseQuery(tag: nil)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }

        guard let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    /// Mengambil nilai asli untuk satu tag. Memicu dialog Touch ID/Face ID
    /// sendiri (terpisah dari approval command) lewat `ApprovalGate` di
    /// level kode kita — item Keychain-nya sendiri tidak punya ACL
    /// biometrik (lihat catatan di `add`), jadi gate ini WAJIB lolos
    /// dulu sebelum `SecItemCopyMatching` dipanggil.
    func resolve(tag: String, reason: String, gate: ApprovalGate) throws -> String {
        guard gate.approve(reason: reason) else {
            throw SecretStoreError.approvalDenied(tag)
        }

        var query = baseQuery(tag: tag)
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw SecretStoreError.notFound(tag) }
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return secret
    }
}

// MARK: - Secure terminal input (tanpa echo ke layar)

func readSecret(prompt: String) -> String? {
    FileHandle.standardOutput.write("\(prompt): ".data(using: .utf8)!)

    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)
    var newTermios = oldTermios
    newTermios.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

    let line = readLine()

    tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
    print()
    return line
}

// MARK: - Target host per request (`#GATEWAY-HOST: <host>` di baris pertama)

let hostDirectivePattern = try! NSRegularExpression(pattern: "^#GATEWAY-HOST:\\s*(\\S+)")

/// Baca host target dari baris PERTAMA file request, kalau ada
/// (`#GATEWAY-HOST: <host>`). Baris ini tetap valid sebagai komentar bash
/// biasa (diawali `#`), jadi tidak perlu dihapus sebelum dikirim ke SSH —
/// tetap tampil utuh di terminal/audit log. Kalau tidak ada directive,
/// pakai `defaultHost` (dari `GATEWAY_SSH_HOST`/default "pe-server").
func targetHost(for rawCommand: String, default defaultHost: String) -> String {
    guard let firstLine = rawCommand.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
        return defaultHost
    }
    let line = String(firstLine)
    let range = NSRange(line.startIndex..., in: line)
    guard let match = hostDirectivePattern.firstMatch(in: line, range: range),
          let hostRange = Range(match.range(at: 1), in: line) else {
        return defaultHost
    }
    return String(line[hostRange])
}

// MARK: - Placeholder resolution ({{pw:tag}})

let passwordPlaceholderPattern = try! NSRegularExpression(pattern: "\\{\\{pw:([A-Za-z0-9_-]+)\\}\\}")

/// Ganti setiap `{{pw:tag}}` di `command` dengan nilai asli dari Keychain.
/// Tidak boleh dipanggil sebelum command mentah (dengan placeholder)
/// selesai ditampilkan/di-log, supaya password tidak pernah masuk ke
/// terminal history atau audit log.
///
/// Resolusi tag sadar-host: untuk `{{pw:sudo}}` di request bertarget host
/// `server-2`, gateway coba tag `sudo@server-2` dulu (dicek lewat
/// `listTags()`, TANPA memicu approval), baru fallback ke tag polos
/// `sudo` kalau versi host-scoped tidak ada. Jadi operator cukup simpan
/// password dengan tag `<tag>@<host>` (mis. `pw add sudo@server-2`) untuk
/// server yang punya password berbeda — tidak perlu prompt interaktif
/// terpisah, karena host request sudah menentukan tag mana yang dipakai.
func resolvePlaceholders(in command: String, host: String, using store: SecretStore, gate: ApprovalGate) throws -> String {
    var resolved = command
    let nsRange = NSRange(command.startIndex..., in: command)
    let matches = passwordPlaceholderPattern.matches(in: command, range: nsRange)
    var cache: [String: String] = [:]
    let existingTags = (try? store.listTags()) ?? []

    for match in matches.reversed() {
        guard let tagRange = Range(match.range(at: 1), in: command) else { continue }
        let tag = String(command[tagRange])

        let secret: String
        if let cached = cache[tag] {
            secret = cached
        } else {
            let scopedTag = "\(tag)@\(host)"
            let tagToUse = existingTags.contains(scopedTag) ? scopedTag : tag
            secret = try store.resolve(tag: tagToUse, reason: "Ambil password '\(tagToUse)' untuk eksekusi command gateway di \(host)", gate: gate)
            cache[tag] = secret
        }

        guard let fullRange = Range(match.range, in: resolved) else { continue }
        resolved.replaceSubrange(fullRange, with: secret)
    }

    return resolved
}

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

// MARK: - Request processing

func writeResponse(id: String, payload: [String: Any], to responsesDir: URL) {
    let responseURL = responsesDir.appendingPathComponent("\(id).json")
    guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }
    try? jsonData.write(to: responseURL)
}

func processRequest(fileURL: URL, config: GatewayConfig, gate: ApprovalGate, executor: SSHExecutor, logger: AuditLogger, secrets: SecretStore) {
    let id = fileURL.deletingPathExtension().lastPathComponent

    guard let rawCommand = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("[\(id)] Gagal membaca file request, skip.")
        return
    }

    // Host target bisa override per-request lewat baris pertama
    // `#GATEWAY-HOST: <host>`; kalau tidak ada, pakai default config.
    let host = targetHost(for: rawCommand, default: config.sshHost)

    // Selalu tampilkan/log versi MENTAH (placeholder {{pw:tag}} belum
    // diresolve) — supaya password tidak pernah muncul di terminal/log.
    print("========================================")
    print("Request baru: \(id)")
    print("Host target : \(host)")
    print("Isi command (placeholder password belum diresolve):")
    print(rawCommand)
    print("========================================")

    let reason = "Setujui eksekusi command \"\(id)\" di \(host)?"
    let approved = gate.approve(reason: reason)
    let timestamp = ISO8601DateFormatter().string(from: Date())

    var payload: [String: Any] = [
        "id": id,
        "timestamp": timestamp,
        "host": host,
        "approved": approved
    ]

    if approved {
        print("[\(id)] Disetujui. Menyiapkan command (resolve password tag bila ada)...")

        do {
            let resolvedCommand = try resolvePlaceholders(in: rawCommand, host: host, using: secrets, gate: gate)
            print("[\(id)] Menjalankan di \(host)...")
            let result = executor.run(host: host, script: resolvedCommand)
            payload["exitCode"] = result.exitCode
            payload["stdout"] = result.stdout
            payload["stderr"] = result.stderr
            print("[\(id)] Selesai. exit_code=\(result.exitCode)")

            logger.append(AuditEntry(
                id: id, timestamp: timestamp, host: host,
                command: rawCommand, approved: true, exitCode: result.exitCode
            ))
        } catch {
            print("[\(id)] Gagal resolve password tag: \(error)")
            payload["exitCode"] = NSNull()
            payload["stdout"] = ""
            payload["stderr"] = "Gagal resolve password tag: \(error)"

            logger.append(AuditEntry(
                id: id, timestamp: timestamp, host: host,
                command: rawCommand, approved: true, exitCode: nil
            ))
        }
    } else {
        print("[\(id)] Ditolak atau approval gagal. Command tidak dijalankan.")
        payload["exitCode"] = NSNull()
        payload["stdout"] = ""
        payload["stderr"] = "Request ditolak atau Touch ID/Face ID gagal."

        logger.append(AuditEntry(
            id: id, timestamp: timestamp, host: host,
            command: rawCommand, approved: false, exitCode: nil
        ))
    }

    writeResponse(id: id, payload: payload, to: config.responsesDir)

    let processedURL = config.processedDir.appendingPathComponent(fileURL.lastPathComponent)
    try? FileManager.default.removeItem(at: processedURL)
    try? FileManager.default.moveItem(at: fileURL, to: processedURL)
}

// MARK: - `pw` subcommand (kelola password per tag)

func runPasswordSubcommand(_ args: [String], store: SecretStore, gate: ApprovalGate) -> Never {
    func usageAndExit() -> Never {
        print("""
        Penggunaan:
          cli-approval-gateway pw add <tag>     Tambah/ubah password dengan tag
          cli-approval-gateway pw edit <tag>    Alias untuk add (ubah nilai tag yang sudah ada)
          cli-approval-gateway pw show <tag>    Cek apakah tag tersimpan (TIDAK menampilkan nilai)
          cli-approval-gateway pw list          Daftar NAMA tag yang tersimpan (TIDAK menampilkan nilai)
          cli-approval-gateway pw reveal <tag>  Tampilkan nilai ASLI (wajib Touch ID/Face ID) —
                                                 KHUSUS OPERATOR, agent TIDAK BOLEH menjalankan ini
          cli-approval-gateway pw remove <tag>  Hapus password dengan tag
          cli-approval-gateway pw delete <tag>  Alias untuk remove

        Multi-server: kalau beberapa server punya password berbeda untuk
        placeholder yang sama (mis. {{pw:sudo}}), simpan dengan tag
        host-scoped: "<tag>@<host>", contoh:
          cli-approval-gateway pw add sudo@pe-server-2
        Saat memproses request bertarget host "pe-server-2", gateway coba
        tag "sudo@pe-server-2" dulu, baru fallback ke tag polos "sudo"
        kalau versi host-scoped tidak ada.
        """)
        exit(1)
    }

    guard let action = args.first else { usageAndExit() }

    switch action {
    case "add", "edit":
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        let promptLabel = action == "edit" ? "Masukkan password BARU untuk tag '\(tag)'" : "Masukkan password untuk tag '\(tag)'"
        guard let secret = readSecret(prompt: promptLabel), !secret.isEmpty else {
            print("Dibatalkan, password kosong.")
            exit(1)
        }
        do {
            try store.add(tag: tag, secret: secret)
            print("Tersimpan: tag '\(tag)' (wajib Touch ID/Face ID saat diambil/ditampilkan).")
            exit(0)
        } catch {
            print("Gagal menyimpan tag '\(tag)': \(error)")
            exit(1)
        }

    case "show":
        // Sengaja TIDAK menampilkan nilai asli, hanya konfirmasi tag ada
        // atau tidak — lihat insiden 2026-11-06 (password bocor ke
        // transcript lewat `pw list`/`pw show`) di personal-docs. Tidak
        // perlu approval Touch ID karena tidak ada nilai yang terbuka.
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        do {
            let tags = try store.listTags()
            if tags.contains(tag) {
                print("Tag '\(tag)' tersimpan di Keychain.")
            } else {
                print("Tag '\(tag)' TIDAK ditemukan di Keychain.")
            }
            exit(0)
        } catch {
            print("Gagal cek tag '\(tag)': \(error)")
            exit(1)
        }

    case "reveal":
        // Satu-satunya subcommand yang menampilkan nilai ASLI password.
        // Khusus dipakai operator sendiri di terminalnya — agent (Claude
        // Code atau agent lain) TIDAK BOLEH menjalankan ini lewat Bash
        // tool/otomatis apa pun, karena stdout-nya akan masuk ke
        // transcript percakapan sama seperti insiden `pw list`/`pw show`
        // 2026-11-06 (lihat personal-docs). Nama "reveal" sengaja dibuat
        // berbeda dari "show"/"list" supaya aturan larangan untuk agent
        // mudah ditegakkan tanpa ambigu.
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        do {
            let secret = try store.resolve(tag: tag, reason: "Tampilkan password '\(tag)' ke terminal Anda", gate: gate)
            print("Password untuk tag '\(tag)':")
            print(secret)
            exit(0)
        } catch {
            print("Gagal menampilkan tag '\(tag)': \(error)")
            exit(1)
        }

    case "list":
        // Hanya nama tag, bukan nilainya — lihat catatan di atas pada
        // case "show".
        do {
            let tags = try store.listTags()
            if tags.isEmpty {
                print("Belum ada tag tersimpan.")
            } else {
                print("Tag tersimpan:")
                for tag in tags {
                    print("  - \(tag)")
                }
            }
            exit(0)
        } catch {
            print("Gagal membaca daftar tag: \(error)")
            exit(1)
        }

    case "remove", "delete":
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        do {
            try store.remove(tag: tag)
            print("Tag '\(tag)' dihapus.")
            exit(0)
        } catch {
            print("Gagal menghapus tag '\(tag)': \(error)")
            exit(1)
        }

    default:
        usageAndExit()
    }
}

// MARK: - Entry point

let secretStore = SecretStore()
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

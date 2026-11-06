// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Error reporting

func reportRequestError(id: String, stage: String, _ message: String) {
    let line = "[\(id)] ERROR tahap=\(stage): \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

// MARK: - Response persistence

enum ResponseWriteError: Error, CustomStringConvertible {
    case encodeFailed
    case writeFailed(Error)

    var description: String {
        switch self {
        case .encodeFailed: return "gagal serialize response JSON"
        case .writeFailed(let error): return "gagal menulis response: \(error)"
        }
    }
}

/// Tulis response JSON ke file sementara di `responsesDir`, lalu rename/replace
/// atomik ke `<id>.json`. Pembaca tidak pernah melihat response setengah tertulis.
func writeResponseAtomic(id: String, payload: [String: Any], to responsesDir: URL) throws {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
        throw ResponseWriteError.encodeFailed
    }

    let finalURL = responsesDir.appendingPathComponent("\(id).json")
    let tempURL = responsesDir.appendingPathComponent("\(id).\(UUID().uuidString).tmp")

    do {
        try jsonData.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tempURL)
    } catch {
        try? FileManager.default.removeItem(at: tempURL)
        throw ResponseWriteError.writeFailed(error)
    }
}

// MARK: - Duplicate ID detection

/// Benar bila `id` sudah memiliki state di `processing/`, `processed/`, atau
/// `responses/` — artinya ID ini sudah pernah diklaim/diselesaikan dan TIDAK
/// boleh dipakai lagi untuk menjalankan command.
func requestIDHasExistingState(_ id: String, config: GatewayConfig) -> Bool {
    let fm = FileManager.default
    let candidates = [
        config.processingDir.appendingPathComponent("\(id).sh"),
        config.processingDir.appendingPathComponent("\(id).status.json"),
        config.processedDir.appendingPathComponent("\(id).sh"),
        config.responsesDir.appendingPathComponent("\(id).json")
    ]
    return candidates.contains { fm.fileExists(atPath: $0.path) }
}

/// ID sudah dipakai sebelumnya: tolak tanpa approval/eksekusi, keluarkan
/// request dari `requests/`, dan tulis response penolakan bila belum ada
/// response terminal untuk ID tersebut.
func rejectDuplicateRequest(fileURL: URL, id: String, config: GatewayConfig) {
    reportRequestError(id: id, stage: "claim", "ID sudah memiliki state (processing/processed/responses); request baru dengan ID yang sama ditolak.")

    let responseURL = config.responsesDir.appendingPathComponent("\(id).json")
    if !FileManager.default.fileExists(atPath: responseURL.path) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "id": id,
            "timestamp": timestamp,
            "host": "",
            "approved": false,
            "exitCode": NSNull(),
            "stdout": "",
            "stderr": "Request ditolak: ID \"\(id)\" sudah pernah diklaim/diproses sebelumnya.",
            "status": "duplicate-id-rejected"
        ]
        do {
            try writeResponseAtomic(id: id, payload: payload, to: config.responsesDir)
        } catch {
            reportRequestError(id: id, stage: "duplicate-response-write", "\(error)")
        }
    }

    // Pindahkan file duplikat keluar dari requests/ dengan nama unik supaya
    // tidak terus-menerus dipungut ulang oleh poll berikutnya, dan tidak
    // bertabrakan dengan file processed/<id>.sh milik eksekusi yang sah.
    let strayURL = config.processedDir.appendingPathComponent("\(id).duplicate.\(UUID().uuidString).sh")
    try? FileManager.default.moveItem(at: fileURL, to: strayURL)
}

// MARK: - Claim

/// Klaim request secara atomik dengan rename `requests/<id>.sh` ->
/// `processing/<id>.sh` pada filesystem yang sama. Mengembalikan URL baru di
/// `processing/` bila berhasil, atau nil bila gagal (watcher lain sudah
/// mengklaim lebih dulu, atau file sudah tidak ada).
func claimRequest(fileURL: URL, config: GatewayConfig) -> URL? {
    let id = fileURL.deletingPathExtension().lastPathComponent
    let destinationURL = config.processingDir.appendingPathComponent(fileURL.lastPathComponent)

    do {
        try FileManager.default.moveItem(at: fileURL, to: destinationURL)
        return destinationURL
    } catch {
        // Race normal antar-watcher: file sudah dipindah/hilang sebelum kita
        // sampai di sini. Bukan error yang perlu dilaporkan sebagai kegagalan.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            reportRequestError(id: id, stage: "claim", "Gagal mengklaim request: \(error)")
        }
        return nil
    }
}

/// Pindahkan satu file request kandidat dari `requests/` ke pemrosesan penuh.
/// Menangani deteksi ID duplikat lalu klaim atomik sebelum approval.
func handleCandidateRequest(fileURL: URL, config: GatewayConfig, gate: ApprovalGating, executor: CommandExecuting, logger: AuditLogger, secrets: SecretStore) {
    let id = fileURL.deletingPathExtension().lastPathComponent

    if requestIDHasExistingState(id, config: config) {
        rejectDuplicateRequest(fileURL: fileURL, id: id, config: config)
        return
    }

    guard let claimedURL = claimRequest(fileURL: fileURL, config: config) else {
        return
    }

    processClaimedRequest(fileURL: claimedURL, config: config, gate: gate, executor: executor, logger: logger, secrets: secrets)
}

// MARK: - Finalize (move to processed/)

/// Hanya dipanggil setelah response terminal berhasil tersimpan secara
/// durable. Memindahkan `.sh` dari `processing/` ke `processed/` dan
/// membersihkan sidecar status.
func finalizeProcessing(id: String, fileURL: URL, config: GatewayConfig) {
    let processedURL = config.processedDir.appendingPathComponent(fileURL.lastPathComponent)
    try? FileManager.default.removeItem(at: processedURL)
    do {
        try FileManager.default.moveItem(at: fileURL, to: processedURL)
        removeRequestStatus(id: id, in: config.processingDir)
    } catch {
        reportRequestError(id: id, stage: "finalize-move", "Response sudah tersimpan tetapi gagal memindahkan request ke processed/: \(error). Request tetap di processing/ untuk pemeriksaan manual.")
    }
}

// MARK: - Request processing (request sudah diklaim, berada di processing/)

func processClaimedRequest(fileURL: URL, config: GatewayConfig, gate: ApprovalGating, executor: CommandExecuting, logger: AuditLogger, secrets: SecretStore) {
    let id = fileURL.deletingPathExtension().lastPathComponent

    guard let rawCommand = try? String(contentsOf: fileURL, encoding: .utf8) else {
        reportRequestError(id: id, stage: "read", "Gagal membaca file request setelah diklaim. Request tetap di processing/ untuk pemeriksaan manual.")
        return
    }

    // Host target bisa override per-request lewat baris pertama
    // `#GATEWAY-HOST: <host>`; kalau tidak ada, pakai default config.
    let host = targetHost(for: rawCommand, default: config.sshHost)

    do {
        try writeRequestStatus(RequestStatus(id: id, stage: .claimed, host: host, timestamp: ISO8601DateFormatter().string(from: Date())), to: config.processingDir)
    } catch {
        reportRequestError(id: id, stage: "status-claimed", "Gagal menulis status klaim: \(error). Request tetap di processing/ untuk pemeriksaan manual.")
        return
    }

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
            try writeRequestStatus(RequestStatus(id: id, stage: .sshStarted, host: host, timestamp: timestamp), to: config.processingDir)
        } catch {
            reportRequestError(id: id, stage: "status-ssh-started", "Gagal mencatat status sebelum eksekusi: \(error). Command TIDAK dijalankan demi keamanan.")
            payload["exitCode"] = NSNull()
            payload["stdout"] = ""
            payload["stderr"] = "Gagal mencatat status sebelum eksekusi; command tidak dijalankan untuk mencegah eksekusi tanpa jejak recovery."
            payload["status"] = "aborted-before-execution"
            finishProcessing(id: id, fileURL: fileURL, payload: payload, config: config)
            return
        }

        do {
            let resolvedCommand = try resolvePlaceholders(in: rawCommand, host: host, using: secrets, gate: gate)
            print("[\(id)] Menjalankan di \(host)...")
            let result = executor.run(host: host, script: resolvedCommand)
            payload["exitCode"] = result.exitCode
            payload["stdout"] = result.stdout
            payload["stderr"] = result.stderr
            print("[\(id)] Selesai. exit_code=\(result.exitCode)")

            do {
                try logger.append(AuditEntry(
                    id: id, timestamp: timestamp, host: host,
                    command: rawCommand, approved: true, exitCode: result.exitCode
                ))
            } catch {
                reportRequestError(id: id, stage: "audit", "Gagal menulis audit log: \(error). Response tetap disimpan.")
            }
        } catch {
            print("[\(id)] Gagal resolve password tag: \(error)")
            payload["exitCode"] = NSNull()
            payload["stdout"] = ""
            payload["stderr"] = "Gagal resolve password tag: \(error)"

            do {
                try logger.append(AuditEntry(
                    id: id, timestamp: timestamp, host: host,
                    command: rawCommand, approved: true, exitCode: nil
                ))
            } catch {
                reportRequestError(id: id, stage: "audit", "Gagal menulis audit log: \(error). Response tetap disimpan.")
            }
        }
    } else {
        print("[\(id)] Ditolak atau approval gagal. Command tidak dijalankan.")
        payload["exitCode"] = NSNull()
        payload["stdout"] = ""
        payload["stderr"] = "Request ditolak atau Touch ID/Face ID gagal."

        do {
            try logger.append(AuditEntry(
                id: id, timestamp: timestamp, host: host,
                command: rawCommand, approved: false, exitCode: nil
            ))
        } catch {
            reportRequestError(id: id, stage: "audit", "Gagal menulis audit log: \(error). Response tetap disimpan.")
        }
    }

    finishProcessing(id: id, fileURL: fileURL, payload: payload, config: config)
}

/// Tulis response secara atomik dan hanya pindahkan ke `processed/` bila
/// penulisan berhasil. Bila gagal, request tetap di `processing/` (dengan
/// status terakhirnya) untuk pemeriksaan manual — tidak kembali ke pending.
private func finishProcessing(id: String, fileURL: URL, payload: [String: Any], config: GatewayConfig) {
    do {
        try writeResponseAtomic(id: id, payload: payload, to: config.responsesDir)
        finalizeProcessing(id: id, fileURL: fileURL, config: config)
    } catch {
        reportRequestError(id: id, stage: "response-write", "\(error). Request tetap di processing/ untuk pemeriksaan manual; TIDAK akan dijalankan ulang otomatis.")
    }
}

// MARK: - Recovery saat startup

/// Dipanggil sebelum watcher mulai memindai `requests/`. Memeriksa setiap
/// request yang masih tertinggal di `processing/` dari sesi sebelumnya
/// (crash/restart) dan menyelesaikannya tanpa pernah menjalankan ulang SSH
/// secara otomatis.
func recoverInterruptedRequests(config: GatewayConfig, logger: AuditLogger) {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: config.processingDir, includingPropertiesForKeys: nil) else {
        return
    }

    let shFiles = files.filter { $0.pathExtension == "sh" }

    for fileURL in shFiles {
        let id = fileURL.deletingPathExtension().lastPathComponent
        let responseURL = config.responsesDir.appendingPathComponent("\(id).json")

        // Response terminal sudah ada: gateway lama sempat menyimpan response
        // tapi crash sebelum memindahkan file ke processed/. Selesaikan saja.
        if fm.fileExists(atPath: responseURL.path) {
            finalizeProcessing(id: id, fileURL: fileURL, config: config)
            continue
        }

        let status = readRequestStatus(id: id, in: config.processingDir)
        let host = status?.host ?? ""
        let timestamp = ISO8601DateFormatter().string(from: Date())

        var payload: [String: Any] = [
            "id": id,
            "timestamp": timestamp,
            "host": host,
            "exitCode": NSNull(),
            "stdout": ""
        ]

        switch status?.stage {
        case .sshStarted:
            payload["approved"] = true
            payload["status"] = "execution-unknown"
            payload["stderr"] = "Gateway berhenti setelah command dikirim ke SSH; hasil eksekusi remote TIDAK diketahui. Periksa server \(host) sebelum mengirim request baru dengan ID baru."
            reportRequestError(id: id, stage: "recovery", "ssh-started tanpa response terminal; ditandai execution-unknown, tidak dijalankan ulang.")
        default:
            payload["approved"] = false
            payload["status"] = "recovery-interrupted"
            payload["stderr"] = "Gateway berhenti sebelum eksekusi SSH dimulai; command tidak dijalankan. Kirim request baru dengan ID baru bila masih diperlukan."
            reportRequestError(id: id, stage: "recovery", "Diklaim tapi SSH belum dimulai saat gateway berhenti; tidak dijalankan ulang otomatis.")
        }

        do {
            try writeResponseAtomic(id: id, payload: payload, to: config.responsesDir)
            finalizeProcessing(id: id, fileURL: fileURL, config: config)
        } catch {
            reportRequestError(id: id, stage: "recovery-response-write", "\(error). Request tetap di processing/ (\(fileURL.path)) untuk pemeriksaan manual.")
        }
    }

    // Sidecar status tanpa file .sh yang cocok (seharusnya tidak terjadi,
    // tapi jangan tertinggal selamanya sebagai sampah).
    let orphanStatusFiles = files.filter { $0.path.hasSuffix(".status.json") }
    for statusURL in orphanStatusFiles {
        let id = statusURL.lastPathComponent.replacingOccurrences(of: ".status.json", with: "")
        let shURL = config.processingDir.appendingPathComponent("\(id).sh")
        if !fm.fileExists(atPath: shURL.path) {
            try? fm.removeItem(at: statusURL)
        }
    }
}

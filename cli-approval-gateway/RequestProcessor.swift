// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

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

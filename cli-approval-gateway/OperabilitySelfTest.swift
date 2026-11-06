// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

private struct SelfTestHostValidator: SSHHostValidating {
    let valid: Bool
    func isValid(_ host: String) -> Bool { valid }
}

private final class SelfTestApprovalGate: ApprovalGating {
    let result: Bool
    private(set) var callCount = 0

    init(result: Bool) { self.result = result }

    func approve(reason: String) -> Bool {
        callCount += 1
        return result
    }
}

private final class SelfTestCommandExecutor: CommandExecuting {
    let result: CommandResult
    private(set) var callCount = 0

    init(result: CommandResult) { self.result = result }

    func run(host: String, script: String) -> CommandResult {
        callCount += 1
        return result
    }
}

private struct SelfTestContext {
    let config: GatewayConfig
    let logger: AuditLogger
    let secrets: SecretStore

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("cli-approval-gateway-operability-\(UUID().uuidString)", isDirectory: true)
        let requests = base.appendingPathComponent("requests", isDirectory: true)
        let processing = base.appendingPathComponent("processing", isDirectory: true)
        let responses = base.appendingPathComponent("responses", isDirectory: true)
        let processed = base.appendingPathComponent("processed", isDirectory: true)
        for directory in [requests, processing, responses, processed] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        config = GatewayConfig(
            baseDir: base,
            requestsDir: requests,
            processingDir: processing,
            responsesDir: responses,
            processedDir: processed,
            auditLogURL: base.appendingPathComponent("audit.log"),
            lockFileURL: base.appendingPathComponent("watcher.lock"),
            sshHost: "selftest-host",
            pollIntervalSeconds: 1,
            sshTimeoutSeconds: 0.25,
            auditLogMaxBytes: 1,
            idleHeartbeatSeconds: 1
        )
        logger = AuditLogger(url: config.auditLogURL, maxBytes: config.auditLogMaxBytes)
        secrets = SecretStore(
            baseService: "com.cli-approval-gateway.operability-selftest.\(UUID().uuidString)",
            registryURL: base.appendingPathComponent("secret-bundles.json")
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: config.baseDir)
    }

    func writeRequest(id: String, script: String = "echo selftest") {
        try? script.write(to: config.requestsDir.appendingPathComponent("\(id).sh"), atomically: true, encoding: .utf8)
    }

    func response(id: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: config.responsesDir.appendingPathComponent("\(id).json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

func runOperabilitySelfTest() -> Bool {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append(message)
            print("[selftest] GAGAL: \(message)")
        }
    }

    print("[selftest] Skenario: timeout subprocess dan output parsial")
    check(runSSHTimeoutSelfTest(), "timeout harus menghentikan proses dan mempertahankan output parsial")

    print("[selftest] Skenario: heartbeat hanya dicetak setelah interval idle")
    let heartbeatStart = Date(timeIntervalSince1970: 100)
    var lastHeartbeat = heartbeatStart
    check(idleHeartbeatIfDue(lastHeartbeat: &lastHeartbeat, now: heartbeatStart.addingTimeInterval(299), interval: 300) == nil, "heartbeat tidak boleh dicetak sebelum ambang")
    let heartbeat = idleHeartbeatIfDue(lastHeartbeat: &lastHeartbeat, now: heartbeatStart.addingTimeInterval(300), interval: 300)
    check(heartbeat?.hasPrefix("[idle] menunggu request...") == true, "heartbeat harus dicetak saat ambang tercapai")
    check(idleHeartbeatIfDue(lastHeartbeat: &lastHeartbeat, now: heartbeatStart.addingTimeInterval(301), interval: 300) == nil, "heartbeat tidak boleh berulang setiap iterasi polling")

    print("[selftest] Skenario: validasi alias SSH dan penolakan host tidak dikenal")
    let configURL = FileManager.default.temporaryDirectory.appendingPathComponent("ssh-config-selftest-\(UUID().uuidString)")
    do {
        try "Host selftest-alias\n  HostName 192.0.2.10\n".write(to: configURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configURL) }
        let validator = SSHHostValidator(sshConfigURL: configURL, hostnameResolver: { _ in false })
        check(validator.isValid("selftest-alias"), "alias SSH yang didefinisikan harus valid")
        check(!validator.isValid("unknown-selftest.invalid"), "host yang tidak dikenal harus ditolak")
    } catch {
        check(false, "gagal menyiapkan SSH config sementara: \(error)")
    }

    print("[selftest] Skenario: timeout menghasilkan response terminal")
    do {
        let context = try SelfTestContext()
        defer { context.cleanup() }
        let id = "timed-out-selftest"
        let gate = SelfTestApprovalGate(result: true)
        let executor = SelfTestCommandExecutor(result: CommandResult(exitCode: 15, stdout: "parsial", stderr: "", timedOut: true))
        context.writeRequest(id: id)
        handleCandidateRequest(
            fileURL: context.config.requestsDir.appendingPathComponent("\(id).sh"),
            config: context.config,
            gate: gate,
            executor: executor,
            logger: context.logger,
            secrets: context.secrets,
            hostValidator: SelfTestHostValidator(valid: true)
        )
        let response = context.response(id: id)
        check(response?["status"] as? String == "timed-out", "response harus mencatat status timed-out")
        check(response?["stdout"] as? String == "parsial", "response timeout harus menyimpan output parsial")
        check(FileManager.default.fileExists(atPath: context.config.processedDir.appendingPathComponent("\(id).sh").path), "request timeout harus difinalisasi ke processed/")
        check(!FileManager.default.fileExists(atPath: context.config.processingDir.appendingPathComponent("\(id).sh").path), "request timeout tidak boleh tertinggal di processing/")
    } catch {
        check(false, "gagal menyiapkan self-test timeout lifecycle: \(error)")
    }

    print("[selftest] Skenario: host tidak dikenal ditolak sebelum approval")
    do {
        let context = try SelfTestContext()
        defer { context.cleanup() }
        let id = "host-unknown-selftest"
        let gate = SelfTestApprovalGate(result: true)
        let executor = SelfTestCommandExecutor(result: CommandResult(exitCode: 0, stdout: "", stderr: ""))
        context.writeRequest(id: id, script: "#GATEWAY-HOST: typo.invalid\necho selftest")
        handleCandidateRequest(
            fileURL: context.config.requestsDir.appendingPathComponent("\(id).sh"),
            config: context.config,
            gate: gate,
            executor: executor,
            logger: context.logger,
            secrets: context.secrets,
            hostValidator: SelfTestHostValidator(valid: false)
        )
        check(context.response(id: id)?["status"] as? String == "host-unknown", "response host typo harus berstatus host-unknown")
        check(gate.callCount == 0 && executor.callCount == 0, "host tidak dikenal tidak boleh meminta approval atau menjalankan SSH")
        check(FileManager.default.fileExists(atPath: context.config.processedDir.appendingPathComponent("\(id).sh").path), "host-unknown harus difinalisasi")
    } catch {
        check(false, "gagal menyiapkan self-test validasi host: \(error)")
    }

    print("[selftest] Skenario: kegagalan notifikasi tidak menghentikan request")
    do {
        let context = try SelfTestContext()
        defer { context.cleanup() }
        let id = "notification-failure-selftest"
        let gate = SelfTestApprovalGate(result: true)
        let executor = SelfTestCommandExecutor(result: CommandResult(exitCode: 0, stdout: "ok", stderr: ""))
        let missingExecutable = URL(fileURLWithPath: "/tmp/cli-approval-gateway-missing-osascript-\(UUID().uuidString)")
        var notificationFailed = false
        context.writeRequest(id: id)
        handleCandidateRequest(
            fileURL: context.config.requestsDir.appendingPathComponent("\(id).sh"),
            config: context.config,
            gate: gate,
            executor: executor,
            logger: context.logger,
            secrets: context.secrets,
            hostValidator: SelfTestHostValidator(valid: true),
            notifier: { requestID, host in
                notificationFailed = !sendApprovalNotification(id: requestID, host: host, executableURL: missingExecutable)
            }
        )
        check(notificationFailed, "self-test harus mensimulasikan osascript yang tidak tersedia")
        check(context.response(id: id)?["exitCode"] as? Int == 0, "request tetap harus selesai setelah notifikasi gagal")
    } catch {
        check(false, "gagal menyiapkan self-test notifikasi: \(error)")
    }

    print("[selftest] Skenario: rotasi audit dan cleanup pasangan lama")
    do {
        let context = try SelfTestContext()
        defer { context.cleanup() }
        let rotatingLogger = AuditLogger(url: context.config.auditLogURL, maxBytes: 1)
        let firstEntry = AuditEntry(id: "audit-first", timestamp: "2026-01-01T00:00:00Z", host: "selftest", command: "true", approved: true, exitCode: 0)
        let secondEntry = AuditEntry(id: "audit-second", timestamp: "2026-01-01T00:00:01Z", host: "selftest", command: "true", approved: true, exitCode: 0)
        try rotatingLogger.append(firstEntry)
        try rotatingLogger.append(secondEntry)
        let rotated = try String(contentsOf: context.config.auditLogURL.appendingPathExtension("1"), encoding: .utf8)
        let current = try String(contentsOf: context.config.auditLogURL, encoding: .utf8)
        check(rotated.contains("audit-first") && current.contains("audit-second"), "rotasi harus mempertahankan entri lama dan menulis entri baru ke audit.log")

        let now = Date()
        let oldProcessed = context.config.processedDir.appendingPathComponent("old.sh")
        let oldResponse = context.config.responsesDir.appendingPathComponent("old.json")
        let newProcessed = context.config.processedDir.appendingPathComponent("new.sh")
        let newResponse = context.config.responsesDir.appendingPathComponent("new.json")
        let orphanResponse = context.config.responsesDir.appendingPathComponent("orphan.json")
        for url in [oldProcessed, oldResponse, newProcessed, newResponse, orphanResponse] {
            try Data("selftest".utf8).write(to: url)
        }
        let oldDate = now.addingTimeInterval(-40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldProcessed.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldResponse.path)
        let pairs = try cleanupPairs(olderThanDays: 30, config: context.config, now: now)
        check(pairs.map(\.id) == ["old"], "cleanup hanya boleh memilih pasangan yang dua filenya sudah melewati ambang")
        check(FileManager.default.fileExists(atPath: oldProcessed.path) && FileManager.default.fileExists(atPath: oldResponse.path), "pencarian cleanup/dry-run tidak boleh menghapus file")
        try removeCleanupPairs(pairs)
        check(!FileManager.default.fileExists(atPath: oldProcessed.path) && !FileManager.default.fileExists(atPath: oldResponse.path), "cleanup harus menghapus kedua file pasangan lama")
        check(FileManager.default.fileExists(atPath: newProcessed.path) && FileManager.default.fileExists(atPath: newResponse.path), "cleanup tidak boleh menghapus pasangan baru")
        check(FileManager.default.fileExists(atPath: orphanResponse.path), "cleanup tidak boleh menghapus response tanpa pasangan processed")
    } catch {
        check(false, "self-test retensi gagal: \(error)")
    }

    if failures.isEmpty {
        print("[selftest] BERHASIL: seluruh skenario operability lulus.")
        return true
    }
    print("[selftest] GAGAL: \(failures.count) skenario operability tidak lulus.")
    return false
}

// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Integration self-test: lifecycle penuh
//
// Dijalankan lewat `cli-approval-gateway selftest lifecycle`. Memakai test
// double untuk approval (`FixedApprovalGate`) dan eksekusi SSH
// (`FakeCommandExecutor`) lewat protokol `ApprovalGating`/`CommandExecuting`
// sehingga tidak pernah memicu Touch ID/Face ID atau koneksi SSH asli.
// Setiap skenario bekerja di direktori sementara terisolasi (bukan
// `~/.cli-approval-gateway/` operator) dan dibersihkan di akhir.

private struct FixedApprovalGate: ApprovalGating {
    let result: Bool
    func approve(reason: String) -> Bool { result }
}

private final class FakeCommandExecutor: CommandExecuting {
    private(set) var callCount = 0
    var resultToReturn = CommandResult(exitCode: 0, stdout: "ok", stderr: "")

    func run(host: String, script: String) -> CommandResult {
        callCount += 1
        return resultToReturn
    }
}

private struct LifecycleTestContext {
    let config: GatewayConfig
    let logger: AuditLogger
    let secrets: SecretStore

    static func make(label: String) -> LifecycleTestContext {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("cli-approval-gateway-selftest-\(label)-\(UUID().uuidString)", isDirectory: true)
        let requests = base.appendingPathComponent("requests", isDirectory: true)
        let processing = base.appendingPathComponent("processing", isDirectory: true)
        let responses = base.appendingPathComponent("responses", isDirectory: true)
        let processed = base.appendingPathComponent("processed", isDirectory: true)
        for dir in [base, requests, processing, responses, processed] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let config = GatewayConfig(
            baseDir: base, requestsDir: requests, processingDir: processing,
            responsesDir: responses, processedDir: processed,
            auditLogURL: base.appendingPathComponent("audit.log"),
            lockFileURL: base.appendingPathComponent("watcher.lock"),
            sshHost: "selftest-host", pollIntervalSeconds: 1.0
        )
        return LifecycleTestContext(
            config: config,
            logger: AuditLogger(url: config.auditLogURL),
            secrets: SecretStore(service: "com.cli-approval-gateway.selftest.\(UUID().uuidString)")
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: config.baseDir)
    }

    func writeRequest(id: String, script: String = "echo hello") {
        try? script.write(to: config.requestsDir.appendingPathComponent("\(id).sh"), atomically: true, encoding: .utf8)
    }

    func readResponse(id: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: config.responsesDir.appendingPathComponent("\(id).json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func existsInProcessing(id: String) -> Bool {
        FileManager.default.fileExists(atPath: config.processingDir.appendingPathComponent("\(id).sh").path)
    }

    func existsInProcessed(id: String) -> Bool {
        FileManager.default.fileExists(atPath: config.processedDir.appendingPathComponent("\(id).sh").path)
    }
}

private final class LifecycleSelfTestRunner {
    private var failures: [String] = []

    func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append(message)
            print("[selftest]   GAGAL: \(message)")
        }
    }

    func run() -> Bool {
        scenarioApprovalRejected()
        scenarioSSHSuccess()
        scenarioSSHFailure()
        scenarioResponseWriteFailure()
        scenarioRestartBeforeSSHStarted()
        scenarioRestartAfterSSHStarted()
        scenarioRestartAfterResponseWritten()
        scenarioDuplicateIDNotReexecuted()

        if failures.isEmpty {
            print("[selftest] BERHASIL: semua skenario lifecycle lulus.")
            return true
        } else {
            print("[selftest] GAGAL: \(failures.count) skenario tidak lulus.")
            return false
        }
    }

    private func scenarioApprovalRejected() {
        print("[selftest] Skenario: approval ditolak")
        let ctx = LifecycleTestContext.make(label: "rejected")
        defer { ctx.cleanup() }
        let id = "rejected-1"
        let executor = FakeCommandExecutor()
        ctx.writeRequest(id: id)

        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: false), executor: executor, logger: ctx.logger, secrets: ctx.secrets)

        guard let response = ctx.readResponse(id: id) else {
            check(false, "rejected: response tidak ditemukan"); return
        }
        check((response["approved"] as? Bool) == false, "rejected: approved harus false")
        check(response["exitCode"] is NSNull, "rejected: exitCode harus null")
        check(executor.callCount == 0, "rejected: SSH tidak boleh dijalankan")
        check(ctx.existsInProcessed(id: id), "rejected: request harus pindah ke processed/")
    }

    private func scenarioSSHSuccess() {
        print("[selftest] Skenario: SSH sukses")
        let ctx = LifecycleTestContext.make(label: "sshok")
        defer { ctx.cleanup() }
        let id = "ssh-ok-1"
        let executor = FakeCommandExecutor()
        executor.resultToReturn = CommandResult(exitCode: 0, stdout: "hasil-sukses", stderr: "")
        ctx.writeRequest(id: id)

        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: true), executor: executor, logger: ctx.logger, secrets: ctx.secrets)

        guard let response = ctx.readResponse(id: id) else {
            check(false, "ssh-ok: response tidak ditemukan"); return
        }
        check((response["approved"] as? Bool) == true, "ssh-ok: approved harus true")
        check((response["exitCode"] as? Int) == 0, "ssh-ok: exitCode harus 0")
        check((response["stdout"] as? String) == "hasil-sukses", "ssh-ok: stdout harus sesuai")
        check(executor.callCount == 1, "ssh-ok: SSH harus dijalankan tepat sekali")
        check(ctx.existsInProcessed(id: id), "ssh-ok: request harus pindah ke processed/")
    }

    private func scenarioSSHFailure() {
        print("[selftest] Skenario: SSH gagal (exit code bukan nol)")
        let ctx = LifecycleTestContext.make(label: "sshfail")
        defer { ctx.cleanup() }
        let id = "ssh-fail-1"
        let executor = FakeCommandExecutor()
        executor.resultToReturn = CommandResult(exitCode: 1, stdout: "", stderr: "command gagal di remote")
        ctx.writeRequest(id: id)

        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: true), executor: executor, logger: ctx.logger, secrets: ctx.secrets)

        guard let response = ctx.readResponse(id: id) else {
            check(false, "ssh-fail: response tidak ditemukan"); return
        }
        check((response["exitCode"] as? Int) == 1, "ssh-fail: exitCode harus 1")
        check((response["stderr"] as? String) == "command gagal di remote", "ssh-fail: stderr harus tersimpan")
        check(executor.callCount == 1, "ssh-fail: SSH harus tetap dijalankan tepat sekali")
        check(ctx.existsInProcessed(id: id), "ssh-fail: request harus pindah ke processed/ meski exit code gagal")
    }

    private func scenarioResponseWriteFailure() {
        print("[selftest] Skenario: penulisan response gagal")
        let ctx = LifecycleTestContext.make(label: "respfail")
        defer { ctx.cleanup() }
        let id = "resp-fail-1"
        let executor = FakeCommandExecutor()
        ctx.writeRequest(id: id)

        // Buat responsesDir "rusak" dengan menaruh FILE (bukan direktori)
        // bernama sama dengan file sementara target, sehingga write/rename
        // response gagal tanpa harus mengubah permission filesystem.
        try? FileManager.default.removeItem(at: ctx.config.responsesDir)
        try? "bukan direktori".write(to: ctx.config.responsesDir, atomically: true, encoding: .utf8)

        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: true), executor: executor, logger: ctx.logger, secrets: ctx.secrets)

        check(ctx.readResponse(id: id) == nil, "resp-fail: tidak boleh ada response valid yang terbaca")
        check(ctx.existsInProcessing(id: id), "resp-fail: request harus TETAP di processing/, bukan hilang atau balik ke requests/")
        check(!ctx.existsInProcessed(id: id), "resp-fail: request tidak boleh dianggap selesai di processed/")
        check(executor.callCount == 1, "resp-fail: SSH tetap sempat dijalankan sekali sebelum gagal menyimpan response")
    }

    private func scenarioRestartBeforeSSHStarted() {
        print("[selftest] Skenario: restart sebelum SSH dimulai (status claimed saja)")
        let ctx = LifecycleTestContext.make(label: "restart-claimed")
        defer { ctx.cleanup() }
        let id = "restart-claimed-1"
        let fm = FileManager.default
        try? "echo hello".write(to: ctx.config.processingDir.appendingPathComponent("\(id).sh"), atomically: true, encoding: .utf8)
        try? writeRequestStatus(RequestStatus(id: id, stage: .claimed, host: "selftest-host", timestamp: "2026-01-01T00:00:00Z"), to: ctx.config.processingDir)

        recoverInterruptedRequests(config: ctx.config, logger: ctx.logger)

        guard let response = ctx.readResponse(id: id) else {
            check(false, "restart-claimed: response recovery tidak ditemukan"); return
        }
        check((response["status"] as? String) == "recovery-interrupted", "restart-claimed: status harus recovery-interrupted")
        check((response["approved"] as? Bool) == false, "restart-claimed: approved harus false (SSH belum pernah dimulai)")
        check(ctx.existsInProcessed(id: id), "restart-claimed: request harus pindah ke processed/ setelah recovery")
        check(!fm.fileExists(atPath: ctx.config.processingDir.appendingPathComponent("\(id).status.json").path), "restart-claimed: status sidecar harus dibersihkan")

        // Request baru dengan ID yang sama setelah recovery harus ditolak
        // sebagai duplikat, TIDAK dieksekusi otomatis lagi.
        let executor = FakeCommandExecutor()
        ctx.writeRequest(id: id)
        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: true), executor: executor, logger: ctx.logger, secrets: ctx.secrets)
        check(executor.callCount == 0, "restart-claimed: ID yang sudah selesai (walau recovery) tidak boleh dieksekusi ulang otomatis")
    }

    private func scenarioRestartAfterSSHStarted() {
        print("[selftest] Skenario: restart setelah ssh-started (hasil remote tidak diketahui)")
        let ctx = LifecycleTestContext.make(label: "restart-sshstarted")
        defer { ctx.cleanup() }
        let id = "restart-ssh-started-1"
        try? "echo hello".write(to: ctx.config.processingDir.appendingPathComponent("\(id).sh"), atomically: true, encoding: .utf8)
        try? writeRequestStatus(RequestStatus(id: id, stage: .sshStarted, host: "selftest-host", timestamp: "2026-01-01T00:00:00Z"), to: ctx.config.processingDir)

        recoverInterruptedRequests(config: ctx.config, logger: ctx.logger)

        guard let response = ctx.readResponse(id: id) else {
            check(false, "restart-ssh-started: response recovery tidak ditemukan"); return
        }
        check((response["status"] as? String) == "execution-unknown", "restart-ssh-started: status harus execution-unknown")
        check((response["approved"] as? Bool) == true, "restart-ssh-started: approved harus true (sempat lolos approval)")
        check(ctx.existsInProcessed(id: id), "restart-ssh-started: request harus pindah ke processed/ setelah recovery")

        let executor = FakeCommandExecutor()
        ctx.writeRequest(id: id)
        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: true), executor: executor, logger: ctx.logger, secrets: ctx.secrets)
        check(executor.callCount == 0, "restart-ssh-started: ID dengan hasil tidak diketahui tidak boleh dieksekusi ulang otomatis")
    }

    private func scenarioRestartAfterResponseWritten() {
        print("[selftest] Skenario: restart setelah response tersimpan tapi sebelum pindah ke processed/")
        let ctx = LifecycleTestContext.make(label: "restart-afterresp")
        defer { ctx.cleanup() }
        let id = "restart-after-response-1"
        try? "echo hello".write(to: ctx.config.processingDir.appendingPathComponent("\(id).sh"), atomically: true, encoding: .utf8)
        try? writeRequestStatus(RequestStatus(id: id, stage: .sshStarted, host: "selftest-host", timestamp: "2026-01-01T00:00:00Z"), to: ctx.config.processingDir)
        let originalPayload: [String: Any] = ["id": id, "timestamp": "2026-01-01T00:00:00Z", "host": "selftest-host", "approved": true, "exitCode": 0, "stdout": "sudah selesai sebelum crash", "stderr": ""]
        try? writeResponseAtomic(id: id, payload: originalPayload, to: ctx.config.responsesDir)

        recoverInterruptedRequests(config: ctx.config, logger: ctx.logger)

        guard let response = ctx.readResponse(id: id) else {
            check(false, "restart-after-response: response tidak ditemukan"); return
        }
        check((response["stdout"] as? String) == "sudah selesai sebelum crash", "restart-after-response: response asli tidak boleh ditimpa recovery")
        check(ctx.existsInProcessed(id: id), "restart-after-response: request harus diselesaikan ke processed/ tanpa rerun")
    }

    private func scenarioDuplicateIDNotReexecuted() {
        print("[selftest] Skenario: ID yang sudah diselesaikan ditolak bila dikirim ulang")
        let ctx = LifecycleTestContext.make(label: "dup")
        defer { ctx.cleanup() }
        let id = "dup-1"
        let executor = FakeCommandExecutor()
        ctx.writeRequest(id: id)
        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: true), executor: executor, logger: ctx.logger, secrets: ctx.secrets)
        check(executor.callCount == 1, "dup: eksekusi pertama harus terjadi tepat sekali")

        ctx.writeRequest(id: id, script: "echo command-berbeda-dengan-id-sama")
        handleCandidateRequest(fileURL: ctx.config.requestsDir.appendingPathComponent("\(id).sh"), config: ctx.config, gate: FixedApprovalGate(result: true), executor: executor, logger: ctx.logger, secrets: ctx.secrets)
        check(executor.callCount == 1, "dup: ID yang sama TIDAK boleh menyebabkan eksekusi SSH kedua")
    }
}

func runLifecycleSelfTest() -> Bool {
    LifecycleSelfTestRunner().run()
}

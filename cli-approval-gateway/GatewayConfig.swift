// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Configuration

struct GatewayConfig {
    static let defaultSSHHost = "pe-server"
    static let baseDirName = ".cli-approval-gateway"
    static let keychainServiceName = "com.cli-approval-gateway.secrets"
    static let defaultPollIntervalSeconds: TimeInterval = 1.0
    static let defaultSSHTimeoutSeconds: TimeInterval = 120
    static let defaultAuditLogMaxBytes: UInt64 = 10 * 1024 * 1024
    static let defaultIdleHeartbeatSeconds: TimeInterval = 5 * 60

    private static func positiveEnvironmentInterval(_ key: String, fallback: TimeInterval) -> TimeInterval {
        ProcessInfo.processInfo.environment[key]
            .flatMap(TimeInterval.init)
            .flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fallback
    }

    private static func positiveEnvironmentBytes(_ key: String, fallback: UInt64) -> UInt64 {
        ProcessInfo.processInfo.environment[key]
            .flatMap(UInt64.init)
            .flatMap { $0 > 0 ? $0 : nil } ?? fallback
    }

    private static func nonnegativeEnvironmentInterval(_ key: String, fallback: TimeInterval) -> TimeInterval {
        ProcessInfo.processInfo.environment[key]
            .flatMap(TimeInterval.init)
            .flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? fallback
    }

    static var configuredKeychainServiceName: String {
        ProcessInfo.processInfo.environment["GATEWAY_KEYCHAIN_SERVICE_NAME"] ?? keychainServiceName
    }

    /// Lokasi base dir TANPA efek samping (tidak membuat direktori apa
    /// pun) — dipakai untuk membangun path registry bundle password
    /// sebelum `load()` (yang membuat semua subfolder watcher) dipanggil,
    /// supaya subcommand `pw` saja tidak ikut membuat `requests/` dkk.
    static func defaultBaseDirURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(ProcessInfo.processInfo.environment["GATEWAY_BASE_DIR_NAME"] ?? baseDirName, isDirectory: true)
    }

    let baseDir: URL
    let requestsDir: URL
    let processingDir: URL
    let responsesDir: URL
    let processedDir: URL
    let auditLogURL: URL
    let lockFileURL: URL
    let sshHost: String
    let pollIntervalSeconds: TimeInterval
    let sshTimeoutSeconds: TimeInterval
    let auditLogMaxBytes: UInt64
    let idleHeartbeatSeconds: TimeInterval

    static func load() -> GatewayConfig {
        let fm = FileManager.default
        let base = defaultBaseDirURL()
        let requests = base.appendingPathComponent("requests", isDirectory: true)
        let processing = base.appendingPathComponent("processing", isDirectory: true)
        let responses = base.appendingPathComponent("responses", isDirectory: true)
        let processed = base.appendingPathComponent("processed", isDirectory: true)
        let audit = base.appendingPathComponent("audit.log")
        let lock = base.appendingPathComponent("watcher.lock")

        for dir in [base, requests, processing, responses, processed] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let host = ProcessInfo.processInfo.environment["GATEWAY_SSH_HOST"] ?? defaultSSHHost
        return GatewayConfig(
            baseDir: base,
            requestsDir: requests,
            processingDir: processing,
            responsesDir: responses,
            processedDir: processed,
            auditLogURL: audit,
            lockFileURL: lock,
            sshHost: host,
            pollIntervalSeconds: positiveEnvironmentInterval("GATEWAY_POLL_INTERVAL_SECONDS", fallback: defaultPollIntervalSeconds),
            sshTimeoutSeconds: positiveEnvironmentInterval("GATEWAY_SSH_TIMEOUT_SECONDS", fallback: defaultSSHTimeoutSeconds),
            auditLogMaxBytes: positiveEnvironmentBytes("GATEWAY_AUDIT_LOG_MAX_BYTES", fallback: defaultAuditLogMaxBytes),
            idleHeartbeatSeconds: nonnegativeEnvironmentInterval("GATEWAY_IDLE_HEARTBEAT_SECONDS", fallback: defaultIdleHeartbeatSeconds)
        )
    }
}

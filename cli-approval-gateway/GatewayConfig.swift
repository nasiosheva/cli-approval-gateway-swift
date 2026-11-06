// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Configuration

struct GatewayConfig {
    static let defaultSSHHost = "pe-server"
    static let baseDirName = ".cli-approval-gateway"
    static let keychainServiceName = "com.cli-approval-gateway.secrets"
    static let defaultPollIntervalSeconds: TimeInterval = 1.0

    static var configuredKeychainServiceName: String {
        ProcessInfo.processInfo.environment["GATEWAY_KEYCHAIN_SERVICE_NAME"] ?? keychainServiceName
    }

    let baseDir: URL
    let requestsDir: URL
    let processingDir: URL
    let responsesDir: URL
    let processedDir: URL
    let auditLogURL: URL
    let sshHost: String
    let pollIntervalSeconds: TimeInterval

    static func load() -> GatewayConfig {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(ProcessInfo.processInfo.environment["GATEWAY_BASE_DIR_NAME"] ?? baseDirName, isDirectory: true)
        let requests = base.appendingPathComponent("requests", isDirectory: true)
        let processing = base.appendingPathComponent("processing", isDirectory: true)
        let responses = base.appendingPathComponent("responses", isDirectory: true)
        let processed = base.appendingPathComponent("processed", isDirectory: true)
        let audit = base.appendingPathComponent("audit.log")

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
            sshHost: host,
            pollIntervalSeconds: ProcessInfo.processInfo.environment["GATEWAY_POLL_INTERVAL_SECONDS"].flatMap(TimeInterval.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? defaultPollIntervalSeconds
        )
    }
}

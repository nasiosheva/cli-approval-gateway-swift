// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

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
    private let maxBytes: UInt64
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(url: URL, maxBytes: UInt64 = GatewayConfig.defaultAuditLogMaxBytes) {
        self.url = url
        self.maxBytes = maxBytes
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    func append(_ entry: AuditEntry) throws {
        let data = try encoder.encode(entry)
        var line = data
        line.append(10)
        try rotateIfNeeded(forNextEntryBytes: UInt64(line.count))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(line)
    }

    private func rotateIfNeeded(forNextEntryBytes entryBytes: UInt64) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let currentBytes = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentBytes > 0, currentBytes + entryBytes > maxBytes else { return }

        let rotatedURL = url.appendingPathExtension("1")
        if FileManager.default.fileExists(atPath: rotatedURL.path) {
            try FileManager.default.removeItem(at: rotatedURL)
        }
        try FileManager.default.moveItem(at: url, to: rotatedURL)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

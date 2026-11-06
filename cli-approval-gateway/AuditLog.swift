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

    func append(_ entry: AuditEntry) throws {
        let data = try encoder.encode(entry)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
    }
}

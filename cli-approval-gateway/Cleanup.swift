// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

struct CleanupPair {
    let id: String
    let responseURL: URL
    let processedURL: URL
}

private func modificationDate(of url: URL) throws -> Date {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
    guard let date = values.contentModificationDate else {
        throw CocoaError(.fileReadUnknown)
    }
    return date
}

func cleanupPairs(olderThanDays days: Int, config: GatewayConfig, now: Date = Date()) throws -> [CleanupPair] {
    let cutoff = now.addingTimeInterval(-TimeInterval(days) * 24 * 60 * 60)
    let fileManager = FileManager.default
    let processedFiles = try fileManager.contentsOfDirectory(at: config.processedDir, includingPropertiesForKeys: [.contentModificationDateKey])
    let responses = try fileManager.contentsOfDirectory(at: config.responsesDir, includingPropertiesForKeys: [.contentModificationDateKey])
    let responseByID = Dictionary(uniqueKeysWithValues: responses.filter { $0.pathExtension == "json" }.map { ($0.deletingPathExtension().lastPathComponent, $0) })
    return try processedFiles.filter { $0.pathExtension == "sh" }.compactMap { processedURL -> CleanupPair? in
        let id = processedURL.deletingPathExtension().lastPathComponent
        guard let responseURL = responseByID[id],
              try modificationDate(of: processedURL) < cutoff,
              try modificationDate(of: responseURL) < cutoff else {
            return nil
        }
        return CleanupPair(id: id, responseURL: responseURL, processedURL: processedURL)
    }
}

func removeCleanupPairs(_ pairs: [CleanupPair]) throws {
    let fileManager = FileManager.default
    for pair in pairs {
        try fileManager.removeItem(at: pair.responseURL)
        try fileManager.removeItem(at: pair.processedURL)
    }
}

func runCleanupSubcommand(_ args: [String], config: GatewayConfig) -> Never {
    guard args.count == 2 || args.count == 3,
          args.first == "--older-than",
          let days = args.dropFirst().first.flatMap(Int.init), days >= 0,
          args.count == 2 || args[2] == "--dry-run" else {
        FileHandle.standardError.write("Penggunaan: cli-approval-gateway cleanup --older-than <hari> [--dry-run]\n".data(using: .utf8)!)
        exit(2)
    }

    let dryRun = args.count == 3
    do {
        let pairs = try cleanupPairs(olderThanDays: days, config: config)

        if dryRun {
            for pair in pairs {
                print("DRY-RUN id=\(pair.id) response=\(pair.responseURL.lastPathComponent) processed=\(pair.processedURL.lastPathComponent)")
            }
        } else {
            try removeCleanupPairs(pairs)
            for pair in pairs {
                print("CLEANUP id=\(pair.id) removed=response,processed")
            }
        }
        print(dryRun ? "Dry-run selesai. Pasangan yang ditemukan: \(pairs.count)." : "Cleanup selesai. Pasangan yang dihapus: \(pairs.count).")
        exit(0)
    } catch {
        FileHandle.standardError.write("Gagal cleanup: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

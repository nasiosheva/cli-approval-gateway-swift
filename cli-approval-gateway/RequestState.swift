// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Request lifecycle state
//
// Setiap request yang sudah diklaim (berada di `processing/`) punya sidecar
// file `<id>.status.json` yang mencatat tahap terakhir yang berhasil
// diselesaikan. Ini dipakai untuk recovery saat startup: tahap `sshStarted`
// tanpa response terminal berarti hasil remote tidak diketahui dan TIDAK
// boleh dijalankan ulang otomatis.

enum RequestStage: String, Codable {
    case claimed
    case sshStarted = "ssh-started"
}

struct RequestStatus: Codable {
    let id: String
    let stage: RequestStage
    let host: String
    let timestamp: String
}

enum RequestStateError: Error, CustomStringConvertible {
    case encodeFailed
    case writeFailed(Error)

    var description: String {
        switch self {
        case .encodeFailed: return "gagal encode status request"
        case .writeFailed(let error): return "gagal menulis status request: \(error)"
        }
    }
}

func statusFileURL(for id: String, in processingDir: URL) -> URL {
    processingDir.appendingPathComponent("\(id).status.json")
}

/// Tulis status secara atomik (temp file lalu rename) sehingga pembaca tidak
/// pernah melihat file status yang setengah tertulis.
func writeRequestStatus(_ status: RequestStatus, to processingDir: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(status) else {
        throw RequestStateError.encodeFailed
    }

    let finalURL = statusFileURL(for: status.id, in: processingDir)
    let tempURL = processingDir.appendingPathComponent("\(status.id).status.\(UUID().uuidString).tmp")

    do {
        try data.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tempURL)
    } catch {
        try? FileManager.default.removeItem(at: tempURL)
        throw RequestStateError.writeFailed(error)
    }
}

func readRequestStatus(id: String, in processingDir: URL) -> RequestStatus? {
    let url = statusFileURL(for: id, in: processingDir)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(RequestStatus.self, from: data)
}

func removeRequestStatus(id: String, in processingDir: URL) {
    try? FileManager.default.removeItem(at: statusFileURL(for: id, in: processingDir))
}

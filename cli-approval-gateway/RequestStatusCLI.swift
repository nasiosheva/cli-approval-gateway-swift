// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Darwin

private struct StatusResponse: Decodable {
    let id: String
    let status: String?
    let approved: Bool?
    let exitCode: Int?
}

private enum StatusInspectionError: Error, CustomStringConvertible {
    case invalidID, invalidState(String), inaccessible(String), notFound

    var description: String {
        switch self {
        case .invalidID: return "ID harus berupa nama file yang aman."
        case .invalidState(let path): return "State rusak atau tidak valid: \(path)."
        case .inaccessible(let path): return "State tidak dapat diakses: \(path)."
        case .notFound: return "Request tidak ditemukan."
        }
    }
}

private func statusFileExists(_ url: URL) throws -> Bool {
    var info = stat()
    if lstat(url.path, &info) == 0 {
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw StatusInspectionError.invalidState(url.path) }
        return true
    }
    if errno == ENOENT { return false }
    throw StatusInspectionError.inaccessible(url.path)
}

private func readStatusData(_ url: URL) throws -> Data {
    do { return try Data(contentsOf: url) }
    catch { throw StatusInspectionError.inaccessible(url.path) }
}

func runRequestStatusSubcommand(_ args: [String]) -> Never {
    guard args.count == 1 else {
        FileHandle.standardError.write(Data("Penggunaan: cli-approval-gateway status <id>\n".utf8))
        exit(2)
    }
    let id = args[0]
    do {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"),
              id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw StatusInspectionError.invalidID
        }
        let base = GatewayConfig.defaultBaseDirURL()
        let response = base.appendingPathComponent("responses").appendingPathComponent("\(id).json")
        let processing = base.appendingPathComponent("processing")
        let processingRequest = processing.appendingPathComponent("\(id).sh")
        let processed = base.appendingPathComponent("processed").appendingPathComponent("\(id).sh")
        let queued = base.appendingPathComponent("requests").appendingPathComponent("\(id).sh")

        if try statusFileExists(response) {
            let data = try readStatusData(response)
            guard let result = try? JSONDecoder().decode(StatusResponse.self, from: data), result.id == id else {
                throw StatusInspectionError.invalidState(response.path)
            }
            print("Status: terminal\(result.status.map { " (\($0))" } ?? "")")
            if let approved = result.approved { print("Approval: \(approved)") }
            if let exitCode = result.exitCode { print("Exit code: \(exitCode)") }
        } else if try statusFileExists(processingRequest) {
            let sidecar = statusFileURL(for: id, in: processing)
            var stage = ""
            if try statusFileExists(sidecar) {
                let data = try readStatusData(sidecar)
                guard let result = try? JSONDecoder().decode(RequestStatus.self, from: data), result.id == id else {
                    throw StatusInspectionError.invalidState(sidecar.path)
                }
                stage = " (tahap: \(result.stage.rawValue))"
            }
            print("Status: sedang diproses\(stage); watcher belum tentu masih berjalan.")
        } else if try statusFileExists(processed) {
            print("Status: pernah diproses; hasil tidak tersedia.")
        } else if try statusFileExists(queued) {
            print("Status: menunggu dalam antrean.")
        } else {
            throw StatusInspectionError.notFound
        }
        print("Status adalah snapshot dan dapat berubah saat watcher berjalan.")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Gagal memeriksa status: \(error)\n".utf8))
        exit(1)
    }
}

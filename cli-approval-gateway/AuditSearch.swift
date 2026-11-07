// Mories Deo Hutapea,S.E.,S.Kom
import Foundation

struct AuditSearchFilter {
    var host: String?
    var date: String?
    var approved: Bool?

    init(arguments: [String]) throws {
        guard arguments.first == "search" else { throw AuditSearchError.arguments }
        var index = 1
        while index < arguments.count {
            guard index + 1 < arguments.count else { throw AuditSearchError.arguments }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--host" where host == nil && !value.isEmpty: host = value
            case "--date" where date == nil && validAuditDate(value): date = value
            case "--approved" where approved == nil && (value == "true" || value == "false"): approved = value == "true"
            default: throw AuditSearchError.arguments
            }
            index += 2
        }
    }
}

enum AuditSearchError: Error, CustomStringConvertible {
    case arguments, invalidLine(String, Int), unreadable(String)
    var description: String {
        switch self {
        case .arguments: return "Penggunaan: audit search [--host <host>] [--date <YYYY-MM-DD>] [--approved <true|false>]"
        case .invalidLine(let path, let line): return "Baris audit tidak valid: \(path):\(line)"
        case .unreadable(let path): return "Audit tidak dapat dibaca: \(path)"
        }
    }
}

private func validAuditDate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard value.count == 10, let date = formatter.date(from: value) else { return false }
    return formatter.string(from: date) == value
}

func searchAudit(filter: AuditSearchFilter, base: URL) throws -> [AuditEntry] {
    let audit = base.appendingPathComponent("audit.log")
    let formatter = ISO8601DateFormatter()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.calendar = Calendar(identifier: .gregorian)
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dateFormatter.dateFormat = "yyyy-MM-dd"
    var matches: [AuditEntry] = []
    for url in [audit.appendingPathExtension("1"), audit] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch {
            if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileReadNoSuchFileError { continue }
            throw AuditSearchError.unreadable(url.path)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw AuditSearchError.unreadable(url.path) }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        for (index, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8), let entry = try? JSONDecoder().decode(AuditEntry.self, from: data),
                  let timestamp = formatter.date(from: entry.timestamp) ?? fractional.date(from: entry.timestamp) else {
                throw AuditSearchError.invalidLine(url.path, index + 1)
            }
            if let host = filter.host, entry.host != host { continue }
            if let date = filter.date, dateFormatter.string(from: timestamp) != date { continue }
            if let approved = filter.approved, entry.approved != approved { continue }
            matches.append(entry)
        }
    }
    return matches
}

func runAuditSearch(_ arguments: [String]) -> Never {
    do {
        let filter = try AuditSearchFilter(arguments: arguments)
        let entries = try searchAudit(filter: filter, base: GatewayConfig.defaultBaseDirURL())
        if entries.isEmpty { print("Tidak ada hasil audit.") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for entry in entries { print(String(decoding: try encoder.encode(entry), as: UTF8.self)) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Gagal mencari audit: \(error)\n".utf8))
        exit(1)
    }
}

// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

// MARK: - Target host per request (`#GATEWAY-HOST: <host>` di baris pertama)

let hostDirectivePattern = try! NSRegularExpression(pattern: "^#GATEWAY-HOST:\\s*(\\S+)")

/// Baca host target dari baris PERTAMA file request, kalau ada
/// (`#GATEWAY-HOST: <host>`). Baris ini tetap valid sebagai komentar bash
/// biasa (diawali `#`), jadi tidak perlu dihapus sebelum dikirim ke SSH —
/// tetap tampil utuh di terminal/audit log. Kalau tidak ada directive,
/// pakai `defaultHost` (dari `GATEWAY_SSH_HOST`/default "pe-server").
func targetHost(for rawCommand: String, default defaultHost: String) -> String {
    guard let firstLine = rawCommand.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
        return defaultHost
    }
    let line = String(firstLine)
    let range = NSRange(line.startIndex..., in: line)
    guard let match = hostDirectivePattern.firstMatch(in: line, range: range),
          let hostRange = Range(match.range(at: 1), in: line) else {
        return defaultHost
    }
    return String(line[hostRange])
}

// MARK: - Placeholder resolution ({{pw:tag}})

let passwordPlaceholderPattern = try! NSRegularExpression(pattern: "\\{\\{pw:([A-Za-z0-9_-]+)\\}\\}")

/// Ganti setiap `{{pw:tag}}` di `command` dengan nilai asli dari Keychain.
/// Tidak boleh dipanggil sebelum command mentah (dengan placeholder)
/// selesai ditampilkan/di-log, supaya password tidak pernah masuk ke
/// terminal history atau audit log.
///
/// Resolusi tag sadar-host: untuk `{{pw:sudo}}` di request bertarget host
/// `server-2`, gateway coba tag `sudo@server-2` dulu (dicek lewat
/// `listTags()`, TANPA memicu approval), baru fallback ke tag polos
/// `sudo` kalau versi host-scoped tidak ada. Jadi operator cukup simpan
/// password dengan tag `<tag>@<host>` (mis. `pw add sudo@server-2`) untuk
/// server yang punya password berbeda — tidak perlu prompt interaktif
/// terpisah, karena host request sudah menentukan tag mana yang dipakai.
func resolvePlaceholders(in command: String, host: String, using store: SecretStore, gate: ApprovalGating) throws -> String {
    var resolved = command
    let nsRange = NSRange(command.startIndex..., in: command)
    let matches = passwordPlaceholderPattern.matches(in: command, range: nsRange)
    var cache: [String: String] = [:]
    let existingTags = (try? store.listTags()) ?? []

    for match in matches.reversed() {
        guard let tagRange = Range(match.range(at: 1), in: command) else { continue }
        let tag = String(command[tagRange])

        let secret: String
        if let cached = cache[tag] {
            secret = cached
        } else {
            let scopedTag = "\(tag)@\(host)"
            let tagToUse = existingTags.contains(scopedTag) ? scopedTag : tag
            secret = try store.resolve(tag: tagToUse, reason: "Ambil password '\(tagToUse)' untuk eksekusi command gateway di \(host)", gate: gate)
            cache[tag] = secret
        }

        guard let fullRange = Range(match.range, in: resolved) else { continue }
        resolved.replaceSubrange(fullRange, with: secret)
    }

    return resolved
}

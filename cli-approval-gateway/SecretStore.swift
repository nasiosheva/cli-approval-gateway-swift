// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Security

// MARK: - Secret store (macOS Keychain, per tag)

enum SecretStoreError: Error, CustomStringConvertible {
    case osStatus(OSStatus)
    case notFound(String)
    case approvalDenied(String)
    case invalidData

    var description: String {
        switch self {
        case .osStatus(let status):
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "keychain error status \(status)"
        case .notFound(let tag):
            return "Tag '\(tag)' tidak ditemukan di Keychain."
        case .approvalDenied(let tag):
            return "Approval Touch ID/Face ID untuk tag '\(tag)' ditolak/gagal."
        case .invalidData:
            return "Data password tidak valid (bukan UTF-8)."
        }
    }
}

/// Menyimpan password per-tag di macOS Keychain (generic password item),
/// terpisah per tag lewat `kSecAttrAccount`. Pengambilan nilai (`resolve`)
/// dilindungi Touch ID/Face ID oleh access control yang dipasang saat
/// `add`. Tidak ada password yang pernah ditulis ke file/log oleh kelas ini.
final class SecretStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    private func baseQuery(tag: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let tag {
            query[kSecAttrAccount as String] = tag
        }
        return query
    }

    func add(tag: String, secret: String) throws {
        guard let data = secret.data(using: .utf8) else { throw SecretStoreError.invalidData }

        // add = upsert: hapus entry lama dengan tag yang sama dulu.
        try? remove(tag: tag)

        // Catatan: SecAccessControl(.userPresence) sengaja TIDAK dipakai di
        // sini — itu butuh entitlement keychain-access-groups yang hanya
        // tersedia untuk app yang signed dengan Team ID penuh (gagal dengan
        // ad-hoc signing: "A required entitlement is not present"). Gate
        // Touch ID/Face ID untuk pengambilan tetap dipaksa di level kode
        // lewat `ApprovalGate` sebelum `resolve()` dipanggil (lihat
        // `resolvePlaceholders`/pemanggil), bukan oleh ACL Keychain.
        var query = baseQuery(tag: tag)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }
    }

    func remove(tag: String) throws {
        let query = baseQuery(tag: tag)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.osStatus(status)
        }
    }

    func listTags() throws -> [String] {
        var query = baseQuery(tag: nil)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }

        guard let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    /// Mengambil nilai asli untuk satu tag. Memicu dialog Touch ID/Face ID
    /// sendiri (terpisah dari approval command) lewat `ApprovalGate` di
    /// level kode kita — item Keychain-nya sendiri tidak punya ACL
    /// biometrik (lihat catatan di `add`), jadi gate ini WAJIB lolos
    /// dulu sebelum `SecItemCopyMatching` dipanggil.
    func resolve(tag: String, reason: String, gate: ApprovalGating) throws -> String {
        guard gate.approve(reason: reason) else {
            throw SecretStoreError.approvalDenied(tag)
        }

        var query = baseQuery(tag: tag)
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw SecretStoreError.notFound(tag) }
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return secret
    }
}

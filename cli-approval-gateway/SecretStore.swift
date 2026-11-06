// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Security

// MARK: - Secret store (macOS Keychain, per bundle per host)
//
// Setiap host punya "bundle" sendiri — satu kSecAttrService Keychain
// terpisah berisi beberapa tag. Bundle `default` dipakai untuk password
// yang berlaku lintas-host (fallback) ketika bundle host spesifik tidak
// punya tag tersebut. Keychain tidak bisa di-enumerate per-service tanpa
// tahu nama service-nya lebih dulu, jadi nama bundle yang pernah dipakai
// dicatat di `registryURL` (file plaintext kecil, HANYA berisi nama
// bundle, bukan secret apa pun).

enum SecretStoreError: Error, CustomStringConvertible {
    case osStatus(OSStatus)
    case notFound(String, bundle: String)
    case tagAlreadyExists(String, bundle: String)
    case approvalDenied(String)
    case invalidData
    case registryIOError(Error)

    var description: String {
        switch self {
        case .osStatus(let status):
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "keychain error status \(status)"
        case .notFound(let tag, let bundle):
            return "Tag '\(tag)' tidak ditemukan di bundle '\(bundle)'."
        case .tagAlreadyExists(let tag, let bundle):
            return "Tag '\(tag)' sudah ada di bundle '\(bundle)'."
        case .approvalDenied(let tag):
            return "Approval Touch ID/Face ID untuk tag '\(tag)' ditolak/gagal."
        case .invalidData:
            return "Data password tidak valid (bukan UTF-8)."
        case .registryIOError(let error):
            return "Gagal baca/tulis daftar bundle: \(error)"
        }
    }
}

final class SecretStore {
    /// Nama bundle khusus untuk password yang berlaku lintas-host (fallback
    /// ketika bundle host spesifik tidak punya tag yang diminta).
    static let defaultBundle = "default"

    private let baseService: String
    private let registryURL: URL

    init(baseService: String, registryURL: URL) {
        self.baseService = baseService
        self.registryURL = registryURL
    }

    private func keychainService(for bundle: String) -> String {
        "\(baseService).bundle.\(bundle)"
    }

    private func baseQuery(bundle: String, tag: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(for: bundle)
        ]
        if let tag {
            query[kSecAttrAccount as String] = tag
        }
        return query
    }

    func add(tag: String, bundle: String, secret: String) throws {
        guard let data = secret.data(using: .utf8) else { throw SecretStoreError.invalidData }

        // add = upsert: hapus entry lama dengan tag yang sama dulu.
        try? remove(tag: tag, bundle: bundle)

        // Catatan: SecAccessControl(.userPresence) sengaja TIDAK dipakai di
        // sini — itu butuh entitlement keychain-access-groups yang hanya
        // tersedia untuk app yang signed dengan Team ID penuh (gagal dengan
        // ad-hoc signing: "A required entitlement is not present"). Gate
        // Touch ID/Face ID untuk pengambilan tetap dipaksa di level kode
        // lewat `ApprovalGate` sebelum `resolve()` dipanggil (lihat
        // `resolvePlaceholders`/pemanggil), bukan oleh ACL Keychain.
        var query = baseQuery(bundle: bundle, tag: tag)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }

        try registerBundle(bundle)
    }

    func remove(tag: String, bundle: String) throws {
        let query = baseQuery(bundle: bundle, tag: tag)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.osStatus(status)
        }
    }

    func renameTag(from oldTag: String, to newTag: String, bundle: String) throws {
        let tags = try listTags(bundle: bundle)
        guard tags.contains(oldTag) else { throw SecretStoreError.notFound(oldTag, bundle: bundle) }
        guard !tags.contains(newTag) else { throw SecretStoreError.tagAlreadyExists(newTag, bundle: bundle) }

        let query = baseQuery(bundle: bundle, tag: oldTag)
        let attributes = [kSecAttrAccount as String: newTag]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { throw SecretStoreError.notFound(oldTag, bundle: bundle) }
        if status == errSecDuplicateItem { throw SecretStoreError.tagAlreadyExists(newTag, bundle: bundle) }
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }
    }

    func listTags(bundle: String) throws -> [String] {
        var query = baseQuery(bundle: bundle, tag: nil)
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

    /// Mengambil nilai asli untuk satu tag di satu bundle. Memicu dialog
    /// Touch ID/Face ID sendiri (terpisah dari approval command) lewat
    /// `ApprovalGate` di level kode kita — item Keychain-nya sendiri tidak
    /// punya ACL biometrik (lihat catatan di `add`), jadi gate ini WAJIB
    /// lolos dulu sebelum `SecItemCopyMatching` dipanggil.
    func resolve(tag: String, bundle: String, reason: String, gate: ApprovalGating) throws -> String {
        guard gate.approve(reason: reason) else {
            throw SecretStoreError.approvalDenied(tag)
        }

        var query = baseQuery(bundle: bundle, tag: tag)
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw SecretStoreError.notFound(tag, bundle: bundle) }
        guard status == errSecSuccess else { throw SecretStoreError.osStatus(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return secret
    }

    // MARK: - Bundle registry (nama bundle saja, bukan secret)

    func listBundles() throws -> [String] {
        try loadRegistry()
    }

    private func registerBundle(_ bundle: String) throws {
        var bundles = try loadRegistry()
        if !bundles.contains(bundle) {
            bundles.append(bundle)
            bundles.sort()
            try saveRegistry(bundles)
        }
    }

    private func loadRegistry() throws -> [String] {
        guard let data = try? Data(contentsOf: registryURL) else { return [] }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw SecretStoreError.registryIOError(error)
        }
    }

    private func saveRegistry(_ bundles: [String]) throws {
        do {
            try FileManager.default.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(bundles)
            try data.write(to: registryURL, options: .atomic)
        } catch {
            throw SecretStoreError.registryIOError(error)
        }
    }

    // MARK: - Migrasi dari skema lama (satu service flat, tag polos atau "tag@host")

    /// Pindahkan setiap entri lama di service flat `baseService` (skema
    /// sebelum bundle: account "tag" = bundle default, account "tag@host" =
    /// bundle host) ke skema bundle baru, lalu hapus entri lama supaya
    /// tidak ada duplikat yang dapat diakses dua cara. Mengembalikan daftar
    /// "tag -> bundle" yang berhasil dipindah, untuk dilaporkan ke operator.
    func migrateLegacyFlatTags() throws -> [(tag: String, bundle: String)] {
        // Catatan: menggabungkan kSecMatchLimitAll + kSecReturnAttributes +
        // kSecReturnData dalam satu query mengembalikan errSecParam (-50) di
        // Keychain versi macOS ini — jadi ambil daftar account (attributes
        // saja) dulu, baru ambil nilai tiap account satu per satu.
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: baseService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var listResult: CFTypeRef?
        let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &listResult)
        if listStatus == errSecItemNotFound { return [] }
        guard listStatus == errSecSuccess else { throw SecretStoreError.osStatus(listStatus) }
        guard let items = listResult as? [[String: Any]] else { return [] }

        let legacyAccounts = items.compactMap { $0[kSecAttrAccount as String] as? String }

        var migrated: [(tag: String, bundle: String)] = []

        for legacyAccount in legacyAccounts {
            let dataQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: baseService,
                kSecAttrAccount as String: legacyAccount,
                kSecReturnData as String: true
            ]
            var dataResult: CFTypeRef?
            let dataStatus = SecItemCopyMatching(dataQuery as CFDictionary, &dataResult)
            guard dataStatus == errSecSuccess,
                  let data = dataResult as? Data,
                  let secret = String(data: data, encoding: .utf8) else {
                continue
            }

            let tag: String
            let bundle: String
            if let atIndex = legacyAccount.lastIndex(of: "@") {
                tag = String(legacyAccount[legacyAccount.startIndex..<atIndex])
                bundle = String(legacyAccount[legacyAccount.index(after: atIndex)...])
            } else {
                tag = legacyAccount
                bundle = SecretStore.defaultBundle
            }

            try add(tag: tag, bundle: bundle, secret: secret)

            // Verifikasi sebelum hapus entri lama, supaya tidak ada window
            // di mana password tidak bisa diakses dari mana pun kalau ada
            // kegagalan di tengah migrasi.
            let copiedBack = try resolveWithoutApproval(tag: tag, bundle: bundle)
            guard copiedBack == secret else {
                throw SecretStoreError.invalidData
            }

            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: baseService,
                kSecAttrAccount as String: legacyAccount
            ]
            SecItemDelete(deleteQuery as CFDictionary) // best-effort; tag baru sudah tersimpan valid di atas

            migrated.append((tag: tag, bundle: bundle))
        }

        return migrated
    }

    /// Hanya untuk verifikasi internal migrasi — TIDAK memicu approval,
    /// jangan dipakai di luar `migrateLegacyFlatTags`.
    private func resolveWithoutApproval(tag: String, bundle: String) throws -> String {
        var query = baseQuery(bundle: bundle, tag: tag)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.notFound(tag, bundle: bundle)
        }
        return secret
    }
}

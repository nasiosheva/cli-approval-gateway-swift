// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Darwin

// MARK: - `pw` subcommand (kelola password per bundle/host)

/// Ambil nilai `--host <host>` dari args kalau ada, kembalikan sisa args
/// positional tanpa flag tersebut.
private func extractHostFlag(from args: [String]) -> (positional: [String], host: String?) {
    var remaining = args
    guard let flagIndex = remaining.firstIndex(of: "--host"), flagIndex + 1 < remaining.count else {
        return (remaining, nil)
    }
    let host = remaining[flagIndex + 1]
    remaining.remove(at: flagIndex + 1)
    remaining.remove(at: flagIndex)
    return (remaining, host)
}

func runPasswordSubcommand(_ args: [String], store: SecretStore, gate: ApprovalGate) -> Never {
    func usageAndExit() -> Never {
        print("""
        Penggunaan (per BUNDLE, satu bundle = satu host; bundle 'default' = fallback lintas-host):
          cli-approval-gateway pw add <tag> --host <host>     Tambah/ubah password dengan tag di bundle <host>
          cli-approval-gateway pw edit <tag> --host <host>    Alias untuk add
          cli-approval-gateway pw show <tag> --host <host>    Cek apakah tag tersimpan di bundle (TIDAK menampilkan nilai)
          cli-approval-gateway pw list                        Daftar SEMUA bundle dan NAMA tag di tiap bundle (TIDAK menampilkan nilai)
          cli-approval-gateway pw list --host <host>          Daftar NAMA tag di SATU bundle saja
          cli-approval-gateway pw reveal <tag> --host <host>  Tampilkan nilai ASLI (wajib Touch ID/Face ID) —
                                                                KHUSUS OPERATOR, agent TIDAK BOLEH menjalankan ini
          cli-approval-gateway pw remove <tag> --host <host>  Hapus password dengan tag dari bundle
          cli-approval-gateway pw delete <tag> --host <host>  Alias untuk remove
          cli-approval-gateway pw migrate-bundles              Pindahkan tag lama (skema tag@host/tag polos) ke bundle baru

        Multi-server: kalau beberapa server punya password berbeda untuk
        placeholder yang sama (mis. {{pw:sudo}}), simpan di bundle masing-masing:
          cli-approval-gateway pw add sudo --host pe-server-2
        Untuk password yang SAMA di semua host, simpan di bundle 'default':
          cli-approval-gateway pw add sudo --host default
        Saat memproses request bertarget host "pe-server-2", gateway coba
        bundle "pe-server-2" dulu, baru fallback ke bundle "default" kalau
        tag tidak ada di bundle host tersebut.
        """)
        exit(1)
    }

    let (positional, hostFlag) = extractHostFlag(from: args)

    guard let action = positional.first else { usageAndExit() }

    func requireHost() -> String {
        guard let host = hostFlag else { usageAndExit() }
        return host
    }

    switch action {
    case "add", "edit":
        guard positional.count > 1 else { usageAndExit() }
        let tag = positional[1]
        let host = requireHost()
        let promptLabel = action == "edit" ? "Masukkan password BARU untuk tag '\(tag)' (bundle '\(host)')" : "Masukkan password untuk tag '\(tag)' (bundle '\(host)')"
        guard let secret = readSecret(prompt: promptLabel), !secret.isEmpty else {
            print("Dibatalkan, password kosong.")
            exit(1)
        }
        do {
            try store.add(tag: tag, bundle: host, secret: secret)
            print("Tersimpan: tag '\(tag)' di bundle '\(host)' (wajib Touch ID/Face ID saat diambil/ditampilkan).")
            exit(0)
        } catch {
            print("Gagal menyimpan tag '\(tag)' di bundle '\(host)': \(error)")
            exit(1)
        }

    case "show":
        // Sengaja TIDAK menampilkan nilai asli, hanya konfirmasi tag ada
        // atau tidak — lihat insiden 2026-11-06 (password bocor ke
        // transcript lewat `pw list`/`pw show`) di personal-docs. Tidak
        // perlu approval Touch ID karena tidak ada nilai yang terbuka.
        guard positional.count > 1 else { usageAndExit() }
        let tag = positional[1]
        let host = requireHost()
        do {
            let tags = try store.listTags(bundle: host)
            if tags.contains(tag) {
                print("Tag '\(tag)' tersimpan di bundle '\(host)'.")
            } else {
                print("Tag '\(tag)' TIDAK ditemukan di bundle '\(host)'.")
            }
            exit(0)
        } catch {
            print("Gagal cek tag '\(tag)' di bundle '\(host)': \(error)")
            exit(1)
        }

    case "reveal":
        // Satu-satunya subcommand yang menampilkan nilai ASLI password.
        // Khusus dipakai operator sendiri di terminalnya — agent (Claude
        // Code atau agent lain) TIDAK BOLEH menjalankan ini lewat Bash
        // tool/otomatis apa pun, karena stdout-nya akan masuk ke
        // transcript percakapan sama seperti insiden `pw list`/`pw show`
        // 2026-11-06 (lihat personal-docs). Nama "reveal" sengaja dibuat
        // berbeda dari "show"/"list" supaya aturan larangan untuk agent
        // mudah ditegakkan tanpa ambigu.
        guard positional.count > 1 else { usageAndExit() }
        let tag = positional[1]
        let host = requireHost()
        do {
            let secret = try store.resolve(tag: tag, bundle: host, reason: "Tampilkan password '\(tag)' (bundle '\(host)') ke terminal Anda", gate: gate)
            print("Password untuk tag '\(tag)' (bundle '\(host)'):")
            print(secret)
            exit(0)
        } catch {
            print("Gagal menampilkan tag '\(tag)' di bundle '\(host)': \(error)")
            exit(1)
        }

    case "list":
        // Hanya nama bundle/tag, bukan nilainya — lihat catatan di atas
        // pada case "show".
        do {
            if let host = hostFlag {
                let tags = try store.listTags(bundle: host)
                if tags.isEmpty {
                    print("Bundle '\(host)' belum punya tag.")
                } else {
                    print("Bundle '\(host)':")
                    for tag in tags { print("  - \(tag)") }
                }
            } else {
                let bundles = try store.listBundles()
                if bundles.isEmpty {
                    print("Belum ada bundle/tag tersimpan.")
                } else {
                    for bundle in bundles {
                        let tags = (try? store.listTags(bundle: bundle)) ?? []
                        print("Bundle '\(bundle)':")
                        if tags.isEmpty {
                            print("  (kosong)")
                        } else {
                            for tag in tags { print("  - \(tag)") }
                        }
                    }
                }
            }
            exit(0)
        } catch {
            print("Gagal membaca daftar bundle/tag: \(error)")
            exit(1)
        }

    case "remove", "delete":
        guard positional.count > 1 else { usageAndExit() }
        let tag = positional[1]
        let host = requireHost()
        do {
            try store.remove(tag: tag, bundle: host)
            print("Tag '\(tag)' dihapus dari bundle '\(host)'.")
            exit(0)
        } catch {
            print("Gagal menghapus tag '\(tag)' dari bundle '\(host)': \(error)")
            exit(1)
        }

    case "migrate-bundles":
        do {
            let migrated = try store.migrateLegacyFlatTags()
            if migrated.isEmpty {
                print("Tidak ada tag skema lama yang perlu dipindah.")
            } else {
                print("Dipindah ke skema bundle baru:")
                for entry in migrated {
                    print("  - tag '\(entry.tag)' -> bundle '\(entry.bundle)'")
                }
                print("Entri lama sudah dihapus. Gunakan 'pw list' untuk verifikasi.")
            }
            exit(0)
        } catch {
            print("Gagal migrasi: \(error)")
            exit(1)
        }

    default:
        usageAndExit()
    }
}

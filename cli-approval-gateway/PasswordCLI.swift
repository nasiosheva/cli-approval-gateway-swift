// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Darwin

// MARK: - `pw` subcommand (kelola password per tag)

func runPasswordSubcommand(_ args: [String], store: SecretStore, gate: ApprovalGate) -> Never {
    func usageAndExit() -> Never {
        print("""
        Penggunaan:
          cli-approval-gateway pw add <tag>     Tambah/ubah password dengan tag
          cli-approval-gateway pw edit <tag>    Alias untuk add (ubah nilai tag yang sudah ada)
          cli-approval-gateway pw show <tag>    Cek apakah tag tersimpan (TIDAK menampilkan nilai)
          cli-approval-gateway pw list          Daftar NAMA tag yang tersimpan (TIDAK menampilkan nilai)
          cli-approval-gateway pw reveal <tag>  Tampilkan nilai ASLI (wajib Touch ID/Face ID) —
                                                 KHUSUS OPERATOR, agent TIDAK BOLEH menjalankan ini
          cli-approval-gateway pw remove <tag>  Hapus password dengan tag
          cli-approval-gateway pw delete <tag>  Alias untuk remove

        Multi-server: kalau beberapa server punya password berbeda untuk
        placeholder yang sama (mis. {{pw:sudo}}), simpan dengan tag
        host-scoped: "<tag>@<host>", contoh:
          cli-approval-gateway pw add sudo@pe-server-2
        Saat memproses request bertarget host "pe-server-2", gateway coba
        tag "sudo@pe-server-2" dulu, baru fallback ke tag polos "sudo"
        kalau versi host-scoped tidak ada.
        """)
        exit(1)
    }

    guard let action = args.first else { usageAndExit() }

    switch action {
    case "add", "edit":
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        let promptLabel = action == "edit" ? "Masukkan password BARU untuk tag '\(tag)'" : "Masukkan password untuk tag '\(tag)'"
        guard let secret = readSecret(prompt: promptLabel), !secret.isEmpty else {
            print("Dibatalkan, password kosong.")
            exit(1)
        }
        do {
            try store.add(tag: tag, secret: secret)
            print("Tersimpan: tag '\(tag)' (wajib Touch ID/Face ID saat diambil/ditampilkan).")
            exit(0)
        } catch {
            print("Gagal menyimpan tag '\(tag)': \(error)")
            exit(1)
        }

    case "show":
        // Sengaja TIDAK menampilkan nilai asli, hanya konfirmasi tag ada
        // atau tidak — lihat insiden 2026-11-06 (password bocor ke
        // transcript lewat `pw list`/`pw show`) di personal-docs. Tidak
        // perlu approval Touch ID karena tidak ada nilai yang terbuka.
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        do {
            let tags = try store.listTags()
            if tags.contains(tag) {
                print("Tag '\(tag)' tersimpan di Keychain.")
            } else {
                print("Tag '\(tag)' TIDAK ditemukan di Keychain.")
            }
            exit(0)
        } catch {
            print("Gagal cek tag '\(tag)': \(error)")
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
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        do {
            let secret = try store.resolve(tag: tag, reason: "Tampilkan password '\(tag)' ke terminal Anda", gate: gate)
            print("Password untuk tag '\(tag)':")
            print(secret)
            exit(0)
        } catch {
            print("Gagal menampilkan tag '\(tag)': \(error)")
            exit(1)
        }

    case "list":
        // Hanya nama tag, bukan nilainya — lihat catatan di atas pada
        // case "show".
        do {
            let tags = try store.listTags()
            if tags.isEmpty {
                print("Belum ada tag tersimpan.")
            } else {
                print("Tag tersimpan:")
                for tag in tags {
                    print("  - \(tag)")
                }
            }
            exit(0)
        } catch {
            print("Gagal membaca daftar tag: \(error)")
            exit(1)
        }

    case "remove", "delete":
        guard args.count > 1 else { usageAndExit() }
        let tag = args[1]
        do {
            try store.remove(tag: tag)
            print("Tag '\(tag)' dihapus.")
            exit(0)
        } catch {
            print("Gagal menghapus tag '\(tag)': \(error)")
            exit(1)
        }

    default:
        usageAndExit()
    }
}

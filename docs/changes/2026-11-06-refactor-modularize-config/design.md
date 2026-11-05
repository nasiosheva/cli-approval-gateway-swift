# Design: Refactor modularisasi + hilangkan hardcode

## Pendekatan

Refactor "strangler" per-bagian: pindahkan satu blok tanggung jawab ke
file barunya sendiri, build, jalankan uji skenario inti, baru lanjut ke
blok berikutnya. Tidak melakukan big-bang rewrite satu kali jalan, supaya
kalau ada yang pecah, jelas commit/langkah mana penyebabnya.

Target Xcode (`cli-approval-gateway.xcodeproj`) di-generate otomatis
mengenali semua `.swift` baru di dalam folder target `cli-approval-gateway/`
(file group), tapi tetap perlu dicek manual via `xcodebuild` bahwa file
baru benar-benar ikut dikompilasi (kadang perlu ditambahkan manual ke
`project.pbxproj` / lewat Xcode GUI "Add Files").

## Struktur file baru (rencana)

Semua di dalam folder target `cli-approval-gateway/`, menggantikan isi
`main.swift` saat ini:

```text
cli-approval-gateway/
  GatewayConfig.swift       - struct GatewayConfig + semua default/env var
  AuditLog.swift            - AuditEntry, AuditLogger
  ApprovalGate.swift        - ApprovalGate (Touch ID/Face ID)
  SecretStore.swift         - SecretStoreError, SecretStore (Keychain)
  SecureInput.swift         - readSecret(prompt:) (baca password tanpa echo)
  PlaceholderResolver.swift - passwordPlaceholderPattern, resolvePlaceholders,
                               hostDirectivePattern, targetHost(for:default:)
  SSHExecutor.swift         - CommandResult, SSHExecutor
  RequestProcessor.swift    - writeResponse, processRequest
  PasswordCLI.swift         - runPasswordSubcommand (subcommand `pw`)
  main.swift                - HANYA entry point: wiring semua kelas di atas
                               + loop watcher. Tidak ada definisi
                               type/function baru di sini lagi.
```

Pembagian ini mengikuti batas tanggung jawab yang SUDAH ada di komentar
`// MARK: -` di `main.swift` saat ini — jadi pemecahan file murni
memindahkan blok yang sudah terpisah secara logis, tidak perlu redesain
ulang struktur kode.

## Konfigurasi: hilangkan hardcode

`GatewayConfig.load()` saat ini:

```swift
let host = ProcessInfo.processInfo.environment["GATEWAY_SSH_HOST"] ?? "pe-server"
```

Rencana: semua default dipindah jadi static constant bernama jelas di
`GatewayConfig`, dibaca dari environment variable dengan fallback ke
constant tersebut — bukan literal langsung di tengah fungsi:

```swift
struct GatewayConfig {
    static let defaultSSHHost = "pe-server"
    static let baseDirName = ".cli-approval-gateway"
    static let keychainServiceName = "com.cli-approval-gateway.secrets"
    static let defaultPollIntervalSeconds: TimeInterval = 1.0

    ...

    static func load() -> GatewayConfig {
        let host = ProcessInfo.processInfo.environment["GATEWAY_SSH_HOST"]
            ?? defaultSSHHost
        let pollInterval = ProcessInfo.processInfo.environment["GATEWAY_POLL_INTERVAL_SECONDS"]
            .flatMap(TimeInterval.init) ?? defaultPollIntervalSeconds
        let baseDirNameOverride = ProcessInfo.processInfo.environment["GATEWAY_BASE_DIR_NAME"]
            ?? baseDirName
        ...
    }
}
```

`SecretStore.service` juga baca dari `GatewayConfig.keychainServiceName`
(atau konstanta yang sama) lewat parameter init, bukan literal terpisah
di dalam `SecretStore` sendiri — supaya HANYA ada satu tempat yang
menyatakan nama service Keychain.

**Catatan penting**: `keychainServiceName` sebaiknya TIDAK diubah lewat
environment variable di penggunaan normal — mengubahnya berarti semua
tag password yang sudah tersimpan (`pw add` sebelumnya) menjadi "hilang"
(dicari di service lama, tidak ketemu). Tetap dibuat bisa dioverride demi
konsistensi desain (semua default di satu tempat), tapi didokumentasikan
dengan jelas di `tasks.md`/README bahwa ini bukan hal yang lazim diubah.

## Urutan pengerjaan (strangler, bukan big-bang)

1. Ekstrak `GatewayConfig` dulu (termasuk semua default/env var baru) →
   build → jalankan satu request uji ringan via gateway → pastikan masih
   jalan sama seperti sebelumnya.
2. Pindahkan `AuditLog`, `ApprovalGate`, `SecretStore`, `SecureInput` satu
   per satu (masing-masing tanpa saling bergantung erat) → build tiap
   langkah.
3. Pindahkan `PlaceholderResolver`, `SSHExecutor` → build.
4. Pindahkan `RequestProcessor`, `PasswordCLI` → build.
5. `main.swift` disisakan HANYA entry point (wiring + loop) → build akhir
   → jalankan ulang seluruh skenario uji inti di `tasks.md`.

## Risiko dan rollback

- **Risiko**: akses `private`/`final class` yang berubah makna lintas
  file (Swift `private` di top-level file = scoped ke file itu, bukan ke
  seluruh module) — kalau ada kode yang diam-diam bergantung pada
  `private` dalam file yang sama, pemecahan file bisa menyebabkan error
  compile (bagus, ketahuan saat build) atau — lebih berbahaya — tetap
  compile tapi dengan instance/state yang berbeda dari yang diharapkan.
  Mitigasi: audit setiap `private` yang ada sebelum pindah, ubah jadi
  `internal` (default) kalau memang perlu diakses dari file lain dalam
  module yang sama.
- **Rollback**: karena dikerjakan bertahap dengan build+test di tiap
  langkah, rollback cukup `git checkout -- <file-yang-baru-diubah>` ke
  state sebelum langkah itu (dengan asumsi project ini akan di-git-init —
  lihat catatan di `tasks.md`). Kalau belum sempat di-commit per langkah,
  rollback manual lewat riwayat edit sesi ini.
- Tidak ada perubahan ke server (`pe-server`), Keychain existing, atau
  protokol file-based IPC — jadi tidak ada risiko ke data/credential yang
  sudah tersimpan selama refactor dilakukan benar (tag Keychain tetap
  dicari di service name yang sama selama env var override tidak dipakai).

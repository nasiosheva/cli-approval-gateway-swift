# Tasks: Refactor modularisasi + hilangkan hardcode

Status keseluruhan: **belum dikerjakan** — ini baru rencana (plan), belum
ada implementasi. Checklist di bawah adalah satu-satunya rencana
implementasi aktif untuk change ini (sesuai konvensi OpenSpec repo ini).

## 1. Persiapan

- [ ] 1.1 Pastikan tidak ada gateway yang sedang berjalan sebelum mulai
      (`pgrep -fl "cli-approval-gateway/bin/cli-approval-gateway"`) —
      refactor hanya menyentuh source code, tapi build ulang perlu
      binary lama tidak dipakai sampai selesai diverifikasi.
- [ ] 1.2 Catat hasil `pw list` (nama tag saja — operator yang jalankan,
      bukan agent) SEBELUM refactor sebagai baseline, untuk dibandingkan
      lagi setelah refactor (harus identik).
- [ ] 1.3 (Opsional, didiskusikan dulu dengan operator) kalau project ini
      mau di-`git init` supaya rollback per-langkah lebih mudah — belum
      ada keputusan, project ini belum punya git repo sama sekali.

## 2. Ekstrak `GatewayConfig` + hilangkan hardcode

- [ ] 2.1 Buat `GatewayConfig.swift`, pindahkan `struct GatewayConfig`
      dari `main.swift`.
- [ ] 2.2 Tambah static constant: `defaultSSHHost`, `baseDirName`,
      `keychainServiceName`, `defaultPollIntervalSeconds` (lihat
      `design.md` untuk nilai persisnya — harus SAMA dengan nilai
      hardcode saat ini, supaya tidak ada perubahan behavior).
- [ ] 2.3 Tambah pembacaan env var baru (`GATEWAY_POLL_INTERVAL_SECONDS`,
      `GATEWAY_BASE_DIR_NAME`, `GATEWAY_KEYCHAIN_SERVICE_NAME`) dengan
      fallback ke constant masing-masing.
- [ ] 2.4 Build (`xcodebuild ... build`) — harus sukses.
- [ ] 2.5 Jalankan gateway, kirim 1 request ringan (`echo ...`), approve,
      cek response `approved:true, exitCode:0` — bandingkan dengan
      baseline sebelum refactor.

## 3. Ekstrak `AuditLog`, `ApprovalGate`, `SecretStore`, `SecureInput`

- [ ] 3.1 Buat `AuditLog.swift` (pindahkan `AuditEntry`, `AuditLogger`).
- [ ] 3.2 Buat `ApprovalGate.swift` (pindahkan `ApprovalGate`).
- [ ] 3.3 Buat `SecretStore.swift` (pindahkan `SecretStoreError`,
      `SecretStore`) — `service` baca dari
      `GatewayConfig.keychainServiceName`.
- [ ] 3.4 Buat `SecureInput.swift` (pindahkan `readSecret(prompt:)`).
- [ ] 3.5 Build — harus sukses.
- [ ] 3.6 Operator jalankan `pw list` sendiri di terminalnya, bandingkan
      nama tag dengan baseline task 1.2 — harus identik (service name
      Keychain tidak berubah).

## 4. Ekstrak `PlaceholderResolver`, `SSHExecutor`

- [ ] 4.1 Buat `PlaceholderResolver.swift` (pindahkan
      `passwordPlaceholderPattern`, `resolvePlaceholders`,
      `hostDirectivePattern`, `targetHost(for:default:)`).
- [ ] 4.2 Buat `SSHExecutor.swift` (pindahkan `CommandResult`,
      `SSHExecutor`).
- [ ] 4.3 Build — harus sukses.
- [ ] 4.4 Kirim request dengan placeholder `{{pw:sudo}}` (command yang
      sudah pernah diuji sebelumnya, misalnya cek versi PHP via `sudo`)
      — approve, pastikan `sudo -S` masih bekerja non-interaktif seperti
      sebelum refactor.

## 5. Ekstrak `RequestProcessor`, `PasswordCLI`

- [ ] 5.1 Buat `RequestProcessor.swift` (pindahkan `writeResponse`,
      `processRequest`).
- [ ] 5.2 Buat `PasswordCLI.swift` (pindahkan `runPasswordSubcommand`).
- [ ] 5.3 Build — harus sukses.
- [ ] 5.4 Operator uji `pw add`/`pw edit`/`pw show`/`pw reveal`/
      `pw remove` sendiri di terminalnya (pakai tag uji, BUKAN tag
      production seperti `sudo`/`DBdev`/`DBprod`) — pastikan semua
      subcommand masih berperilaku sama (termasuk `pw reveal` tetap
      satu-satunya yang menampilkan nilai asli).

## 6. Sisakan `main.swift` hanya entry point

- [ ] 6.1 Hapus semua definisi type/function dari `main.swift`, sisakan
      hanya instansiasi + percabangan subcommand + loop watcher.
- [ ] 6.2 Build final — harus sukses, tanpa warning baru.
- [ ] 6.3 Copy binary baru ke `~/.cli-approval-gateway/bin/cli-approval-gateway`.

## 7. Verifikasi ulang skenario inti (regresi)

- [ ] 7.1 Request ringan (`echo ...`) → approve → cek response sama
      seperti sebelum refactor.
- [ ] 7.2 Request dengan `{{pw:sudo}}` → approve → `sudo -S` masih
      bekerja non-interaktif.
- [ ] 7.3 Request dengan directive `#GATEWAY-HOST: <host-lain>` (host uji,
      bukan `pe-server` production) → pastikan `SSHExecutor.run(host:...)`
      memakai host dari directive, bukan default.
- [ ] 7.4 Request dengan tag Keychain yang TIDAK ada
      (`{{pw:tidak-ada-xyz}}`) → pastikan tetap gagal dengan pesan error
      jelas, tidak ada eksekusi SSH yang jalan (regresi dari task 3.5
      di change `2026-11-05-cli-approval-gateway-v1`).
- [ ] 7.5 Approval ditolak (cancel dialog Touch ID) → pastikan tetap
      `approved:false`, tidak ada eksekusi.
- [ ] 7.6 Operator konfirmasi `pw reveal <tag-uji>` masih menampilkan
      nilai asli dengan benar, dan `pw show`/`pw list` masih TIDAK
      menampilkan nilai (regresi dari perbaikan insiden 2026-11-06).

## 8. Dokumentasi

- [ ] 8.1 Update `personal-docs/ide-cli-approval-gateway-deploy-
      2026-11-05.md` (repo `apiperjanjiankerjasama-main`) dengan ringkasan
      hasil refactor (berhasil/gagal, apa yang berubah).
- [ ] 8.2 Tandai `.openspec.yaml` change ini `status: done` setelah semua
      task di atas selesai dan terverifikasi dengan bukti nyata (bukan
      asumsi).

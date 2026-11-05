# Tasks

Setiap task ditandai selesai hanya dengan bukti konkret (output command,
log, atau hasil yang sudah diverifikasi) — bukan asumsi bahwa kode yang
sudah ditulis otomatis berarti perilakunya benar.

## 1. Skeleton watcher + approval + eksekusi SSH

- [x] 1.1 Buat `GatewayConfig`, folder `~/.cli-approval-gateway/{requests,
  responses,processed}`, dan `audit.log` — **selesai, 2026-11-05**: kode
  di `cli-approval-gateway/main.swift`.
- [x] 1.2 `ApprovalGate` via `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`
  — **selesai, 2026-11-05**: kode ada, build sukses. Belum ada bukti dialog
  Touch ID benar-benar muncul dan berfungsi (lihat task 4).
- [x] 1.3 `SSHExecutor` kirim command sebagai stdin ke `ssh <host> bash -s`,
  tangkap stdout/stderr/exit code — **selesai, 2026-11-05**: kode ada,
  build sukses. Belum pernah dieksekusi ke `pe-server` sungguhan.
- [x] 1.4 Tulis response ke `responses/<id>.json`, pindahkan file request
  ke `processed/`, catat ke `audit.log` sebagai JSON Lines — **selesai,
  2026-11-05**: kode ada, build sukses.
- [x] 1.5 Verifikasi build: `xcodebuild -project cli-approval-gateway.xcodeproj
  -scheme cli-approval-gateway -configuration Debug build` — **selesai,
  2026-11-05**: `BUILD SUCCEEDED`, `LocalAuthentication` terlink otomatis
  tanpa konfigurasi tambahan.

## 2. Password store per tag (Keychain)

- [x] 2.1 `SecretStore` (Keychain generic password per tag) dengan
  `add`/`remove`/`listTags`/`resolve` — **selesai, 2026-11-05**, direvisi
  setelah uji live (lihat task 3): awalnya pakai `SecAccessControl`
  `.userPresence` di level Keychain, GAGAL saat uji nyata (lihat 2.1a).
- [x] 2.1a **Temuan uji live**: `pw add` gagal dengan error
  `"A required entitlement is not present."` (errSecMissingEntitlement).
  Root cause: binary ditandatangani ad-hoc (`codesign -dv` menunjukkan
  `TeamIdentifier=not set`), dan `SecAccessControl(.userPresence)` butuh
  entitlement keychain-access-groups yang hanya tersedia untuk app
  signed dengan Team ID penuh. Mencoba set `DEVELOPMENT_TEAM` ke identity
  development yang ada di keychain sistem (`Apple Development:
  deomories@gmail.com`, Team `U4B774TSQY`) GAGAL juga: `xcodebuild` minta
  sertifikat "Mac Development" yang tidak tersedia (identity yang ada
  kemungkinan untuk iOS, bukan macOS).
  **Keputusan**: hapus `SecAccessControl`/`kSecUseDataProtectionKeychain`
  dari item Keychain (jadi generic password biasa, `kSecAttrAccessible =
  WhenUnlockedThisDeviceOnly`), dan pindahkan gate Touch ID/Face ID ke
  level kode — `SecretStore.resolve()` sekarang menerima `ApprovalGate`
  dan memanggil `gate.approve(reason:)` SEBELUM `SecItemCopyMatching`,
  bukan mengandalkan ACL Keychain. Signing project dikembalikan ke
  ad-hoc (`DEVELOPMENT_TEAM` dihapus lagi dari `project.pbxproj`).
  Hasil akhir: properti keamanan yang sama (Touch ID wajib sebelum
  password diambil) tercapai tanpa butuh Team ID/provisioning Apple
  Developer penuh.
- [x] 2.2 Subcommand CLI `pw add|list|remove <tag>`, input password tanpa
  echo terminal (`termios` ECHO off) — **selesai, diverifikasi live
  2026-11-05**: `pw add test-tag` dengan nilai dummy berhasil tersimpan,
  `pw list` menampilkan `test-tag`, `pw remove test-tag` berhasil
  menghapusnya kembali (dibersihkan setelah uji).
- [x] 2.3 Placeholder `{{pw:tag}}` di command + `resolvePlaceholders`,
  substitusi in-memory tepat sebelum kirim ke SSH stdin, command mentah
  (dengan placeholder) yang selalu tampil di terminal/audit log —
  **selesai, diverifikasi live 2026-11-05**: request berisi
  `echo -n "{{pw:test-tag}}" | wc -c` (dikirim ke `pe-server` lewat SSH)
  mengembalikan `21`, persis panjang nilai dummy yang disimpan — konfirmasi
  substitusi bekerja. `audit.log` untuk request itu tetap menyimpan teks
  `{{pw:test-tag}}` literal, nilai asli tidak pernah tercatat.
- [x] 2.4 Ganti `kSecUseOperationPrompt` (deprecated) dengan pendekatan
  gate di kode (lihat 2.1a) — **selesai, 2026-11-05**: build tanpa warning
  deprecation maupun error entitlement.

## 3. Verifikasi live

- [x] 3.1 Jalankan binary dari DerivedData (`GATEWAY_SSH_HOST=pe-server`),
  drop file request read-only (`hostname && whoami && date`) ke
  `requests/` — **selesai, 2026-11-05**: request diproses <3 detik,
  `responses/test-1.json` berisi `stdout` nyata dari `pe-server`
  (`hostname`, `whoami=emon`, `date` sesuai waktu server), `exitCode: 0`,
  `approved: true`. Dialog Touch ID tidak teramati langsung kemungkinan
  karena grace period unlock macOS terbaru pada mesin operator — approval
  tetap tercatat `true` di response dan `audit.log`.
- [x] 3.2 Uji jalur tolak — **selesai, 2026-11-06**: percobaan pertama
  (`test-deny`) lolos otomatis (`approved: true`) tanpa operator sempat
  bereaksi, mengonfirmasi dugaan grace period unlock macOS. Percobaan
  kedua (`test-deny-2`), dengan waktu tunggu lebih lama, dialog Touch ID
  benar-benar muncul dan dibatalkan operator — hasil: `approved: false`,
  `exitCode: null`, `stderr: "Request ditolak atau Touch ID/Face ID
  gagal."`, **tidak ada eksekusi SSH yang terjadi**, `audit.log` mencatat
  `approved:false` dengan benar (field `exitCode` otomatis tidak muncul
  karena nil). Kesimpulan: logika kode untuk jalur tolak BENAR; approval
  cepat tanpa dialog terlihat sebelumnya adalah perilaku macOS (grace
  period recent-auth untuk `.deviceOwnerAuthentication`), bukan bug di
  gateway.
- [x] 3.3 `cli-approval-gateway pw add <tag>` dengan tag uji, konfirmasi
  input tidak ter-echo di terminal, lalu `pw list` menunjukkan tag
  tersebut — **selesai, 2026-11-05** (lihat 2.1a untuk perubahan desain
  yang diperlukan supaya ini berhasil, dan 2.2 untuk detail hasil).
- [x] 3.4 Command request berisi `{{pw:<tag-uji>}}` — **selesai,
  2026-11-05**, lihat 2.3. Belum terkonfirmasi apakah dialog Touch ID
  KEDUA (terpisah dari approval command) benar-benar muncul berbeda dari
  dialog pertama — perlu diuji ulang di luar grace period unlock untuk
  melihat kedua dialog secara visual.
- [ ] 3.5 Uji tag yang tidak ada (`{{pw:tidak-ada}}`), konfirmasi request
  dibatalkan dengan error yang jelas, tidak ada command yang terkirim ke
  SSH. **Belum dilakukan.**
- [ ] 3.6 Catat seluruh bukti task 3.1–3.5 (screenshot/log/isi file) di
  `personal-docs/` project ini — folder sudah ada
  (`personal-docs/README.md`), tapi bukti detail belum dipindah ke sana,
  masih hanya di `tasks.md` ini.

## 4. Keputusan desain yang masih terbuka (lihat design.md Open Questions)

- [ ] 4.1 Putuskan mekanisme identitas/otorisasi per-agent.
- [ ] 4.2 Putuskan perlu/tidak daftar pola command auto-block.
- [ ] 4.3 Putuskan apakah tetap polling atau pindah ke `FSEvents`/
  `DispatchSource`.
- [ ] 4.4 Putuskan mekanisme background process (menu bar app / `launchd`
  agent).
- [ ] 4.5 Putuskan timeout approval otomatis.
- [ ] 4.6 Putuskan proteksi `audit.log` (permission, rotasi, backup).

## 5. Uji live deploy sungguhan (BE dev, 2026-11-05/06)

- [x] 5.1 Gunakan gateway untuk eksekusi deploy "selected-file release" BE
  nyata ke environment dev (`api.monikasda.net` tidak disentuh), mengikuti
  prosedur yang sudah ada di `apiperjanjiankerjasama-main/scripts/` dan
  `personal-docs/cara-deploy-be-selected-file-2026-10-31.md` — **selesai,
  2026-11-05**. Rangkaian: cek state server (read-only) → siapkan bundle
  lokal (`prepare-manual-file-release.sh`) → `scp` bundle + operator
  scripts → verifikasi checksum/`php -l` di server (read-only, via
  gateway) → `pw add sudo` (password sudo, dilakukan operator sendiri,
  tidak lewat gateway/chat) → preflight-only via gateway dengan
  `echo '{{pw:sudo}}' | sudo -S ...` → `--confirm` via gateway → verifikasi
  independen pasca-deploy (checksum + health check, read-only via
  gateway). Bukti lengkap:
  `apiperjanjiankerjasama-main/personal-docs/deploy-packages/
  2026-11-05-5dd35e9a-dev-selected-file/deployment-record.md`.
- [x] 5.2 Konfirmasi placeholder `{{pw:sudo}}` bekerja untuk `sudo -S`
  non-interaktif (bukan hanya untuk DB password seperti task 3.4) —
  **selesai**: command `preflight-dev-be`/`deploy-dev-be-confirm` lulus
  dengan `sudo` tersubstitusi dari Keychain, tanpa TTY interaktif dan tanpa
  password pernah terlihat oleh agent.
- [x] 5.3 Temukan dan perbaiki gap operasional nyata yang tidak kelihatan
  dari kode saja: script `deploy-manual-file-release.sh` menolak jalan
  karena `rollback-manual-file-release.sh` belum ikut ditransfer ke
  staging server — diperbaiki dengan menambah file itu ke `scp`. Lihat
  deployment record untuk detail.

## 6. Subcommand `pw show`/`edit`/`delete` (2026-11-06)

- [x] 6.1 Tambah `pw show <tag>` — menampilkan nilai asli ke terminal
  operator, wajib lolos `ApprovalGate.approve()` (Touch ID/Face ID) dulu
  lewat `SecretStore.resolve()` yang sudah ada, tidak lewat agent/chat
  sama sekali — **selesai, diverifikasi live 2026-11-06**: `pw add
  demo-tag` (dummy) → `pw show demo-tag` mencetak nilai yang benar.
- [x] 6.2 Tambah `pw edit <tag>` sebagai alias `add` (perilaku upsert yang
  sudah ada sebelumnya), dengan label prompt berbeda ("password BARU")
  supaya jelas ini mengganti nilai — **selesai, diverifikasi live
  2026-11-06**: `pw edit demo-tag` berhasil mengganti nilai, dikonfirmasi
  lewat `pw show` menampilkan nilai baru.
- [x] 6.3 Tambah `pw delete <tag>` sebagai alias `remove` — **selesai,
  diverifikasi live 2026-11-06**: `pw delete demo-tag` berhasil, `pw list`
  mengonfirmasi tag hilang, tag `sudo` yang asli tidak terganggu.
- [x] 6.4 Build ulang setelah penambahan: `BUILD SUCCEEDED`.

## 7. Operasional: binary stabil + keputusan manual-start (2026-11-06)

- [x] 7.1 Copy binary hasil build Xcode ke lokasi stabil
  `~/.cli-approval-gateway/bin/cli-approval-gateway` (bukan path
  DerivedData yang hash-nya bisa berubah tiap clean build) — **selesai,
  2026-11-06**.
- [x] 7.2 Coba buat `launchd` agent (`~/Library/LaunchAgents/
  com.cli-approval-gateway.watcher.plist`) supaya gateway auto-start saat
  login — **DIBLOCK** oleh classifier auto-mode Claude Code sendiri
  (kategori "Unauthorized Persistence"). Tidak ada file plist yang
  berhasil tertulis (dikonfirmasi `ls` gagal). Tidak ada workaround yang
  dicoba.
- [x] 7.3 Operator diberi 3 opsi (buat plist manual sendiri / tambah
  permission rule Edit / skip auto-start) — **operator memilih skip
  auto-start**, jalankan manual tiap sesi kerja. Didokumentasikan di
  `CLAUDE.md` repo `apiperjanjiankerjasama-main` (bagian "CLI Approval
  Gateway") supaya sesi Claude Code baru otomatis tahu prosedur ini tanpa
  perlu dijelaskan ulang.
- [x] 7.4 Verifikasi binary stabil (bukan dari DerivedData) bekerja sama
  baiknya — **selesai, 2026-11-06**: jalankan
  `GATEWAY_SSH_HOST=pe-server ~/.cli-approval-gateway/bin/cli-approval-gateway`,
  kirim request `hostname && whoami && date`, response berisi hasil nyata
  dari `pe-server` (`approved: true`, `exitCode: 0`).
- [x] 7.5 Hentikan proses setelah selesai dipakai (`pkill -f
  "cli-approval-gateway/bin/cli-approval-gateway"`) — **selesai,
  2026-11-06**, dikonfirmasi tidak ada proses tersisa.

## Workflow follow-up

- Init git repository untuk project ini (belum git-initialized per
  2026-11-05) — instruksi eksplisit terpisah diperlukan sebelum commit
  pertama.
- Archive change ini setelah task 3 selesai dengan bukti dan task 4
  diputuskan (atau sengaja ditunda dengan catatan alasan).

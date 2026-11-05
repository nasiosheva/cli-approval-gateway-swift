# Spec: Gateway modularization & configuration

## Requirement: Kode gateway dipecah per tanggung jawab ke file terpisah

Gateway HARUS terdiri dari beberapa file Swift, masing-masing dengan satu
tanggung jawab jelas (konfigurasi, audit log, approval gate, secret
store, input aman, resolusi placeholder, eksekusi SSH, pemrosesan
request, subcommand `pw`), dan `main.swift` HARUS hanya berisi entry
point (wiring + loop watcher), tidak ada definisi type/function baru.

#### Scenario: Build tetap sukses setelah file dipecah

- **GIVEN** kode sudah dipecah sesuai struktur file di `design.md`
- **WHEN** `xcodebuild -scheme cli-approval-gateway -configuration Debug build` dijalankan
- **THEN** build sukses (`BUILD SUCCEEDED`) tanpa error maupun warning baru
  terkait akses `private`/visibility antar file

#### Scenario: Tidak ada definisi baru di `main.swift`

- **GIVEN** refactor pemecahan file sudah selesai
- **WHEN** `main.swift` dibaca
- **THEN** isinya hanya instansiasi objek (`GatewayConfig`, `ApprovalGate`,
  `SecretStore`, `SSHExecutor`, `AuditLogger`), percabangan subcommand
  (`pw`), dan loop `while true` watcher — tidak ada `struct`/`class`/
  `func` (selain closure inline) yang didefinisikan langsung di file ini

## Requirement: Nilai konfigurasi tidak hardcode, bisa dioverride via environment variable

Default SSH host, nama folder base, nama service Keychain, dan interval
polling HARUS didefinisikan sebagai constant bernama jelas di satu tempat
(`GatewayConfig`), dan HARUS bisa dioverride lewat environment variable
dengan fallback ke constant tersebut kalau env var tidak diset.

#### Scenario: Default SSH host tetap "pe-server" tanpa env var

- **GIVEN** `GATEWAY_SSH_HOST` tidak diset
- **WHEN** gateway dijalankan
- **THEN** host yang dipakai untuk request tanpa directive
  `#GATEWAY-HOST:` adalah `"pe-server"` (sama seperti sebelum refactor)

#### Scenario: Interval polling bisa dioverride

- **GIVEN** `GATEWAY_POLL_INTERVAL_SECONDS=0.5` diset
- **WHEN** gateway dijalankan
- **THEN** watcher mengecek folder `requests/` setiap 0.5 detik, bukan
  default 1.0 detik

#### Scenario: Nama service Keychain tetap konsisten tanpa override

- **GIVEN** `GATEWAY_KEYCHAIN_SERVICE_NAME` tidak diset
- **WHEN** `pw add`/`pw show`/`pw reveal`/`pw list`/`pw remove` dipanggil
- **THEN** semuanya memakai service name yang sama persis dengan sebelum
  refactor (`com.cli-approval-gateway.secrets`), sehingga tag yang sudah
  tersimpan sebelumnya tetap terbaca

## Requirement: Tidak ada regresi behavior pada skenario yang sudah terverifikasi

Semua perilaku yang sudah terverifikasi bekerja sebelum refactor ini
(lihat change `2026-11-05-cli-approval-gateway-v1`) HARUS tetap bekerja
identik setelah refactor: approval Touch ID, eksekusi SSH nyata, resolusi
placeholder `{{pw:tag}}` (termasuk host-scoped `tag@host`), directive
`#GATEWAY-HOST:`, dan seluruh subcommand `pw` (`add`, `edit`, `show`,
`list`, `reveal`, `remove`, `delete`).

#### Scenario: Request end-to-end tetap berhasil setelah refactor

- **GIVEN** gateway hasil refactor sudah di-build dan dijalankan
- **WHEN** request `.sh` berisi command ringan (`echo ...`) dikirim ke
  `requests/` dan disetujui lewat Touch ID
- **THEN** response di `responses/<id>.json` berisi `approved: true`,
  `exitCode: 0`, dan `stdout` sesuai command — identik dengan hasil
  sebelum refactor

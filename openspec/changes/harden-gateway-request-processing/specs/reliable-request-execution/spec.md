# Spec Delta

## Purpose

Memastikan gateway menangani setiap request command dengan aman saat ada beberapa watcher, kegagalan I/O lokal, restart, atau output SSH yang besar.

## ADDED Requirements

### Requirement: Request diklaim oleh satu watcher
Gateway SHALL mengklaim request secara atomik sebelum meminta approval dan hanya satu instance aktif yang SHALL memproses ID request tersebut. Request yang sudah diklaim SHALL NOT kembali ke antrean pending secara otomatis.

#### Scenario: Dua watcher melihat request yang sama
- **WHEN** dua instance gateway menemukan file request yang sama
- **THEN** hanya satu instance yang mengklaimnya dan request tersebut paling banyak menghasilkan satu approval serta satu eksekusi SSH

#### Scenario: Gateway restart saat hasil eksekusi belum tersimpan
- **WHEN** gateway menemukan request yang sudah diklaim tanpa hasil terminal setelah restart
- **THEN** gateway menandainya sebagai hasil tidak diketahui untuk pemeriksaan operator dan tidak menjalankan ulang command secara otomatis

### Requirement: Hasil dan kegagalan pemrosesan dapat diketahui
Gateway SHALL menyimpan hasil command yang selesai ke response JSON secara atomik. Kegagalan membaca, menulis response atau audit, maupun memindahkan request SHALL dilaporkan dengan tahap dan ID request, dan SHALL NOT mengembalikan request ke pending secara diam-diam.

#### Scenario: Command selesai tetapi response tidak dapat ditulis
- **WHEN** SSH telah selesai tetapi response JSON tidak dapat disimpan
- **THEN** gateway melaporkan kegagalan persistensi ke operator dan mencegah request dijalankan ulang otomatis

#### Scenario: Request gagal dipindahkan dari antrean
- **WHEN** pemindahan request ke status terminal gagal
- **THEN** gateway melaporkan error dan mempertahankan request dalam status yang tidak dipindai sebagai pending

### Requirement: Output SSH dikonsumsi tanpa deadlock
Gateway SHALL mengonsumsi stdout dan stderr proses SSH secara bersamaan sampai kedua stream selesai, lalu melaporkan exit status dan seluruh output yang diterima.

#### Scenario: Kedua stream menghasilkan output besar
- **WHEN** command SSH menulis data melebihi kapasitas pipe ke stdout dan stderr
- **THEN** gateway terus menguras kedua stream, command selesai, dan response memuat output serta exit status tanpa deadlock

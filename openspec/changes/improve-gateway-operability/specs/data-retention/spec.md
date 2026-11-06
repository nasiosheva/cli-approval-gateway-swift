# Spec Delta

## Purpose

Mencegah `audit.log`, `responses/`, dan `processed/` tumbuh tanpa batas selama gateway dipakai dalam jangka panjang.

## ADDED Requirements

### Requirement: Audit log dirotasi berdasarkan ukuran
Gateway SHALL merotasi `audit.log` ke `audit.log.1` ketika entri baru akan melewati ambang `GATEWAY_AUDIT_LOG_MAX_BYTES` (default 10 MiB), dan SHALL melanjutkan penulisan entri baru tanpa kehilangan entri yang sudah tercatat sebelum rotasi.

#### Scenario: Audit log melewati ambang ukuran
- **WHEN** `audit.log` mencapai ukuran ambang saat entri baru akan ditulis
- **THEN** gateway merotasi file saat ini menjadi cadangan dan menulis entri baru ke file `audit.log` yang baru

### Requirement: Operator dapat membersihkan response dan request lama
Gateway SHALL menyediakan subcommand yang menghapus pasangan file di `responses/` dan `processed/` yang lebih tua dari ambang umur yang ditentukan operator, dan SHALL NOT menghapus file apa pun secara otomatis tanpa perintah eksplisit.

#### Scenario: Operator menjalankan cleanup dengan ambang umur
- **WHEN** operator menjalankan subcommand cleanup dengan ambang umur tertentu
- **THEN** gateway menghapus hanya pasangan file di `responses/`/`processed/` yang lebih tua dari ambang tersebut, dan file yang lebih baru tetap ada

#### Scenario: Watcher berjalan tanpa operator memanggil cleanup
- **WHEN** watcher berjalan normal tanpa subcommand cleanup dipanggil
- **THEN** tidak ada file di `responses/` atau `processed/` yang terhapus secara otomatis

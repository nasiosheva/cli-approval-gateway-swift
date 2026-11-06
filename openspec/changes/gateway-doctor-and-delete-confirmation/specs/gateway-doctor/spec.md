# Spec Delta

## Purpose

Membantu operator memeriksa kesiapan lokal gateway dan memahami masalah yang ditemukan.

## ADDED Requirements

### Requirement: Diagnostik kesiapan lokal
CLI SHALL menyediakan `doctor` yang memeriksa direktori data, konfigurasi dasar, ketersediaan SSH dan akses Keychain tanpa membaca atau menampilkan password.

#### Scenario: Pemeriksaan berhasil
- **WHEN** semua pemeriksaan yang tersedia berhasil
- **THEN** CLI menampilkan hasil setiap pemeriksaan dan exit code nol

#### Scenario: Masalah atau pemeriksaan tidak tersedia
- **WHEN** pemeriksaan gagal atau tidak dapat dipastikan tanpa interaksi atau perubahan data
- **THEN** CLI menjelaskan hasil dan langkah perbaikan atau keterbatasannya, serta mengembalikan exit code bukan nol

#### Scenario: Gateway sudah berjalan
- **WHEN** watcher sedang berjalan
- **THEN** doctor tetap dapat memeriksa tanpa menghentikan watcher atau mengubah data gateway

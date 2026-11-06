# Spec Delta

## Purpose

Memberikan gambaran hasil request yang diselesaikan watcher selama sesi yang sedang berjalan.

## ADDED Requirements

### Requirement: Ringkasan sesi watcher
Watcher SHALL menampilkan jumlah berhasil, gagal dan ditolak saat berhenti normal melalui `s`; hitungan dimulai dari nol setiap sesi.

#### Scenario: Hasil request beragam
- **WHEN** sesi menyelesaikan request dengan exit code nol, exit code bukan nol, dan approval ditolak
- **THEN** ringkasan menghitung masing-masing sekali sebagai berhasil, gagal, dan ditolak

#### Scenario: Hasil selain tiga kategori
- **WHEN** request berakhir tanpa exit code dan bukan penolakan approval
- **THEN** ringkasan menghitungnya sebagai gagal dan tidak menyatakan berhasil

#### Scenario: Sesi kosong
- **WHEN** watcher dihentikan sebelum menyelesaikan request
- **THEN** semua hitungan ditampilkan sebagai nol

#### Scenario: Penghentian paksa
- **WHEN** proses berhenti secara paksa atau crash
- **THEN** ringkasan tidak dijamin tersedia dan tidak dianggap sebagai catatan audit permanen

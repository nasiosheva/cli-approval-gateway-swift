# Spec Delta

## Purpose

Memudahkan operator menemukan transaksi audit lokal berdasarkan kriteria yang relevan.

## ADDED Requirements

### Requirement: Pencarian audit
CLI SHALL menyediakan `audit search` dengan filter opsional host, tanggal UTC inklusif dan approval; filter yang diberikan digabungkan dengan AND.

#### Scenario: Filter cocok
- **WHEN** operator memberikan satu atau lebih filter valid
- **THEN** hanya entri yang cocok ditampilkan beserta ID, waktu, host, command mentah, approval dan exit code yang tersedia

#### Scenario: Tidak ada hasil
- **WHEN** tidak ada entri yang cocok atau audit log belum ada
- **THEN** CLI menyatakan tidak ada hasil dan berhasil tanpa mengubah file

#### Scenario: Input atau audit rusak
- **WHEN** filter tidak valid atau baris audit tidak dapat dibaca
- **THEN** CLI melaporkan kesalahan dengan exit code bukan nol dan tidak menyembunyikan kegagalan pembacaan

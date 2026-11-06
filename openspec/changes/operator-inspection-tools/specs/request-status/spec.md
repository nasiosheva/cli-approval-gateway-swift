# Spec Delta

## Purpose

Memungkinkan operator mengetahui keadaan request dari bukti lokal tanpa menjalankan ulang command.

## ADDED Requirements

### Requirement: Pemeriksaan status berdasarkan ID
CLI SHALL menyediakan `status <id>` yang hanya membaca state dan menolak ID yang bukan nama file aman.

#### Scenario: Request dalam antrean
- **WHEN** request ada di `requests/` dan belum ada state yang lebih akhir
- **THEN** CLI menampilkan status menunggu

#### Scenario: Request sedang diproses
- **WHEN** request ada di `processing/` tanpa response
- **THEN** CLI menampilkan sedang diproses dan tahap sidecar jika tersedia, tanpa menjamin proses masih hidup

#### Scenario: Response tersedia
- **WHEN** response tersedia
- **THEN** CLI menampilkan status terminal, approval dan exit code jika tersedia, termasuk status hasil tidak diketahui

#### Scenario: Response telah dihapus
- **WHEN** hanya bukti `processed/` tersedia
- **THEN** CLI menyatakan request pernah diproses dan hasil tidak tersedia tanpa menyimpulkan keberhasilan

#### Scenario: ID tidak ditemukan atau state rusak
- **WHEN** ID tidak ditemukan atau data yang diperlukan tidak dapat dibaca
- **THEN** CLI melaporkan kondisi tersebut dengan exit code bukan nol tanpa mengubah data

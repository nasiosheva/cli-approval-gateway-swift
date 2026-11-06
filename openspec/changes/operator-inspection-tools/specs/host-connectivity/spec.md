# Spec Delta

## Purpose

Memberikan pemeriksaan koneksi SSH eksplisit sebelum operator mengirim request ke host.

## ADDED Requirements

### Requirement: Pemeriksaan SSH noninteraktif
CLI SHALL menyediakan `host check <host>` dengan batas waktu, tanpa prompt, tanpa mengubah known_hosts, dan tanpa menjalankan command pengguna.

#### Scenario: Koneksi terautentikasi
- **WHEN** SSH berhasil menyelesaikan pemeriksaan ke host
- **THEN** CLI melaporkan koneksi berhasil dan exit code nol

#### Scenario: Koneksi gagal
- **WHEN** resolusi host, koneksi, host key, autentikasi atau batas waktu gagal
- **THEN** CLI melaporkan kegagalan dan diagnostik yang tersedia tanpa menebak penyebab jika tidak pasti, serta exit code bukan nol

#### Scenario: Host tidak valid
- **WHEN** host kosong atau dapat ditafsirkan sebagai opsi SSH
- **THEN** CLI menolak input tanpa menjalankan SSH

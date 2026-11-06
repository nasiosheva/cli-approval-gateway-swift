# Design

## Context

State tersebar di `requests/`, `processing/` beserta sidecar, `responses/`, dan `processed/`. Audit berupa JSON Lines; SSH executor saat ini tidak memiliki timeout. Watcher memproses request secara serial. Lihat proposal untuk tujuan.

## Goals / Non-Goals

**Goals:** Pemeriksaan hanya baca, diagnostik SSH terbatas, dan hitungan sesi yang mencerminkan outcome aktual.

**Non-Goals:** Menjalankan ulang command, mengubah approval, menghapus data, dan menjamin ringkasan ketika crash.

## Decisions

- Tambah subcommand `status <id>`, `audit search [--host <host>] [--date <YYYY-MM-DD>] [--approved <true|false>]`, dan `host check <host>`. Parser menolak argumen ekstra. Ini mengikuti dispatcher CLI; alternatif UI interaktif tidak diperlukan.
- Status memakai prioritas response, processing, processed, requests; validasi ID sebelum membangun path. Pembacaan bersifat snapshot dan dapat berubah selama watcher aktif. Response rusak dilaporkan sebagai error, bukan diasumsikan sukses.
- Audit membaca `audit.log` sebagai JSON Lines, filter tanggal berdasarkan hari UTC pada timestamp, dan melaporkan baris rusak. Tidak membaca file rotasi yang belum ada dalam baseline; integrasikan jika change rotasi diterapkan. Tidak menggunakan database agar format tetap kompatibel.
- Pemeriksaan host memakai `/usr/bin/ssh` dengan argumen terpisah, BatchMode, StrictHostKeyChecking=yes, tanpa modifikasi known_hosts, timeout koneksi dan deadline proses, serta command tetap `true`. Output diagnostik dipertahankan; exit SSH saja tidak cukup untuk mengklasifikasikan semua sebab. Pemeriksaan ini melakukan autentikasi dan menjalankan `true` di remote, bukan command pengguna; server dengan forced command dapat berperilaku berbeda. Alternatif TCP saja tidak memverifikasi SSH/auth.
- Hitungan disimpan dalam memori, diperbarui sekali dari outcome yang benar-benar diselesaikan selama sesi, lalu dicetak saat `s`. Recovery startup dan request yang belum memiliki outcome terminal tidak dihitung; ini bukan pengganti audit. Hindari menyimpulkan outcome dari log terminal.

## Risks / Trade-offs

- [State berubah saat dibaca] → tampilkan bukti dan jangan menjamin snapshot konsisten atau watcher masih hidup.
- [SSH mungkin memiliki ProxyCommand atau forced command dari konfigurasi pengguna] → dokumentasikan efek konfigurasi SSH dan batasi waktu keseluruhan proses serta turunannya.
- [Audit memuat command sensitif] → tampilkan hanya saat operator secara eksplisit meminta pencarian, tanpa resolve placeholder.
- [Change lain menambah rotasi atau validasi host] → selaraskan integrasi dan tes saat change tersebut diterapkan.

## Migration Plan

Tidak ada migrasi data. Build dan pasang binary baru; rollback dengan binary sebelumnya. Format response dan audit tetap sama.

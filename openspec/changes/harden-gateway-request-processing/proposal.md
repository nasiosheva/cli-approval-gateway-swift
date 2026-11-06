# Proposal

## Why

Gateway saat ini dapat membaca request yang sama dari lebih dari satu watcher, menelan kegagalan menulis respons atau memindahkan file, dan menunggu output SSH secara berurutan. Kombinasi ini dapat menjalankan command remote berulang, membuat request tampak menggantung, atau menggantungkan gateway saat output besar.

## What Changes

- Klaim request secara atomik sebelum menampilkan approval dan cegah dua watcher memproses request yang sama.
- Tetapkan perilaku pemulihan untuk request yang gateway-nya berhenti saat command remote mungkin sudah berjalan; request dengan hasil eksekusi tak diketahui tidak boleh otomatis dijalankan ulang.
- Laporkan kegagalan baca, tulis respons, audit, dan pemindahan file dengan status yang dapat didiagnosis, tanpa meninggalkan request yang terus diproses ulang diam-diam.
- Baca stdout dan stderr SSH secara bersamaan agar salah satu pipe tidak memblokir proses.
- Pertahankan persetujuan eksplisit sebelum eksekusi dan bentuk respons JSON yang sudah digunakan, kecuali tambahan status diperlukan untuk membedakan hasil tak diketahui.

## Capabilities

### New Capabilities
- `reliable-request-execution`: pemrosesan request satu kali, pemulihan aman, pelaporan hasil, dan penanganan output SSH tanpa deadlock.

### Modified Capabilities

## Impact

Perubahan menyentuh `main.swift`, `RequestProcessor.swift`, `SSHExecutor.swift`, dan dokumentasi protokol request/response. Tidak mengubah format command, autentikasi SSH, penyimpanan Keychain, atau kebijakan approval. Setelah crash saat/selepas SSH dimulai, keberhasilan remote mungkin tidak dapat dipastikan; sistem harus menandai hasil sebagai tidak diketahui dan meminta operator memeriksa sebelum retry.

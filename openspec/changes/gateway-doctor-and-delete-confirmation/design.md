# Design

## Context

`GatewayConfig.load()` membuat direktori, sedangkan `defaultBaseDirURL()` hanya menentukan path. Penghapusan saat ini mengambil lock watcher lalu langsung menghapus. Keychain memiliki akses berbasis service dan dapat memerlukan interaksi sistem.

## Goals / Non-Goals

**Goals:** Diagnostik informatif tanpa membuka secret dan penghapusan dengan persetujuan eksplisit.

**Non-Goals:** Memperbaiki konfigurasi otomatis, mengeksekusi SSH jarak jauh, atau mengganti kebijakan lock.

## Decisions

- Dispatch `doctor` sebelum `GatewayConfig.load()` dan lock watcher. Periksa konfigurasi environment, keberadaan dan akses direktori tanpa membuatnya, executable SSH, dan ketersediaan Keychain melalui pemeriksaan metadata noninteraktif. Jika akses tidak dapat dibuktikan tanpa membaca secret atau interaksi, laporkan tidak dapat dipastikan; jangan mengklaim berhasil. Alternatif tes dengan membuat secret ditolak karena mengubah data.
- Gunakan hasil per pemeriksaan dan exit code bukan nol untuk gagal maupun tidak dapat dipastikan. Jangan cetak nama tag, nilai password, atau detail secret.
- Parse argumen sebelum efek samping; tanpa `--yes`, butuh terminal interaktif dan jawaban `y`/`yes`. Ambil lock sebelum penghapusan, pertahankan lock hingga selesai, dan tampilkan target. Penolakan atau EOF tidak menghapus apa pun. `--yes` memungkinkan skrip yang secara eksplisit menyetujui tindakan.
- Timeout SSH tetap dimiliki `improve-gateway-operability`; jangan duplikasi implementasi. Timeout memutus proses lokal tidak membuktikan command remote berhenti: response dan dokumentasi harus memperingatkan hasil remote mungkin tidak diketahui sebelum mencoba ulang.

## Risks / Trade-offs

- [Pemeriksaan akses berbasis metadata tidak membuktikan semua operasi akan berhasil] → tampilkan keterbatasannya secara eksplisit.
- [Skrip lama tanpa `--yes` gagal] → dokumentasikan perubahan dan migrasi.
- [State berubah setelah pemeriksaan] → jelaskan bahwa doctor adalah snapshot.

## Migration Plan

Perbarui skrip yang memang berwenang menghapus dengan `--yes`; instal binary baru setelah build dan verifikasi. Rollback dengan binary sebelumnya mengembalikan perilaku penghapusan tanpa konfirmasi.

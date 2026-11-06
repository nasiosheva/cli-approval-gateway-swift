# Proposal

## Why

Operator perlu memeriksa status request, menemukan transaksi audit, memeriksa konektivitas SSH, dan memahami aktivitas watcher tanpa menelusuri file secara manual.

## What Changes

- Tambahkan perintah status berdasarkan ID request.
- Tambahkan pencarian audit berdasarkan host, tanggal, dan hasil approval.
- Tambahkan pemeriksaan koneksi SSH host yang terbatas waktu dan tidak menjalankan command pengguna.
- Tampilkan ringkasan jumlah hasil request selama sesi watcher.

Di luar cakupan: retensi data, perubahan protokol approval, dan eksekusi ulang request.

## Capabilities

### New Capabilities

- `request-status`: pemeriksaan status request berdasarkan state yang tersedia.
- `audit-search`: pencarian catatan audit lokal.
- `host-connectivity`: pemeriksaan koneksi SSH secara eksplisit oleh operator.
- `session-summary`: ringkasan aktivitas selama sesi watcher.

### Modified Capabilities

Tidak ada.

## Impact

CLI, pembacaan state dan audit, integrasi SSH, loop watcher, dokumentasi, dan pengujian akan terdampak. Change aktif `improve-gateway-operability` juga membahas validasi host dan rotasi audit; implementasi harus mengoordinasikan perilaku tersebut tanpa mengasumsikan change itu telah diterapkan.

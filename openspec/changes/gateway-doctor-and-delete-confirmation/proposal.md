# Proposal

## Why

Operator memerlukan cara memeriksa kesiapan lokal dan menghindari penghapusan massal karena salah menjalankan perintah. Timeout SSH telah direncanakan tetapi belum diimplementasikan.

## What Changes

- Tambahkan `doctor` untuk pemeriksaan kesiapan lokal tanpa mengungkap password.
- **BREAKING**: `clear-responses` dan `clear-audit` meminta konfirmasi interaktif; `--yes` memungkinkan otomasi eksplisit.
- Timeout SSH tetap dikerjakan dalam change `improve-gateway-operability`, task 1.1, 1.3, 4.1–4.3; tidak diduplikasi di change ini.

Di luar cakupan: pemeriksaan koneksi SSH ke host (direncanakan dalam `operator-inspection-tools`) dan penghapusan otomatis.

## Capabilities

### New Capabilities

- `gateway-doctor`: diagnostik kesiapan lokal yang aman.
- `deletion-confirmation`: konfirmasi eksplisit sebelum penghapusan massal.

### Modified Capabilities

Tidak ada spesifikasi utama yang tersedia.

## Impact

Dispatcher CLI, diagnostik konfigurasi dan Keychain, perintah penghapusan, help, README, dan pengujian. Skrip penghapusan yang ada perlu menambahkan `--yes`.

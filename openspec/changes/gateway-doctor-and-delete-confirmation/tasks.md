# Tasks

## 1. Diagnostik lokal

- [ ] 1.1 Implementasikan pemeriksaan konfigurasi, direktori dan SSH tanpa membuat data; uji kondisi sehat, tidak ada, tidak dapat diakses dan konfigurasi tidak valid.
- [ ] 1.2 Implementasikan pemeriksaan Keychain noninteraktif tanpa membaca secret; uji hasil tersedia, gagal dan tidak dapat dipastikan tanpa mengungkap tag atau password.
- [ ] 1.3 Hubungkan `doctor` sebelum lock watcher dan dokumentasikan keterbatasannya di help/README; verifikasi ketika watcher aktif dan pastikan exit code sesuai.

## 2. Konfirmasi penghapusan

- [ ] 2.1 Validasi argumen dan tambahkan konfirmasi kedua perintah serta `--yes`, dengan lock tetap berlaku; uji setuju, batal, EOF, nonterminal, argumen tidak valid, dan watcher aktif menggunakan data sementara.
- [ ] 2.2 Perbarui help/README dan migrasi skrip untuk `--yes`; verifikasi contoh terdokumentasi dan perilaku tanpa flag.

## 3. Integrasi

- [ ] 3.1 Jalankan build dan self-test yang ada serta tes CLI baru; verifikasi tidak ada data nyata diubah selama pengujian.
- [ ] 3.2 Saat mengerjakan timeout pada change `improve-gateway-operability`, verifikasi output parsial dan status timeout, jelaskan hasil remote mungkin tidak diketahui, serta uji antrean tetap berjalan.

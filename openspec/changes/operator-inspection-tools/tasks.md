# Tasks

## 1. Status request

- [ ] 1.1 Tambahkan pembaca status dan validasi ID aman; uji antrean, processing, response, processed tanpa response, state rusak, dan ID tidak ditemukan.
- [ ] 1.2 Hubungkan `status <id>` ke CLI dan dokumentasikan di help/README; verifikasi contoh serta exit code tanpa mengubah data.

## 2. Pencarian audit

- [ ] 2.1 Implementasikan pembacaan JSON Lines dan filter host, tanggal UTC dan approval; uji kombinasi filter, file kosong/tidak ada, data rusak, dan argumen tidak valid.
- [ ] 2.2 Hubungkan `audit search` dan dokumentasikan opsi di help/README; verifikasi hasil dan exit code pada data contoh.

## 3. Pemeriksaan host

- [ ] 3.1 Implementasikan pemeriksaan SSH noninteraktif dengan validasi host dan deadline keseluruhan; uji melalui proses tiruan untuk sukses, gagal, timeout dan input berbahaya.
- [ ] 3.2 Hubungkan `host check` dan dokumentasikan batasannya di help/README; verifikasi tidak ada prompt atau perubahan known_hosts dalam pengujian terisolasi.

## 4. Ringkasan sesi

- [ ] 4.1 Catat outcome terminal satu kali per request dan tampilkan ringkasan saat `s`; uji outcome campuran, sesi kosong, error, dan pengecualian recovery.
- [ ] 4.2 Dokumentasikan waktu tampil dan batasan ringkasan di help/README; verifikasi contoh pada sesi watcher terisolasi.

## 5. Integrasi

- [ ] 5.1 Jalankan build dan self-test lifecycle, serta tes integrasi CLI baru; pastikan format response/audit dan perilaku approval tetap kompatibel.
- [ ] 5.2 Periksa interaksi dengan change `improve-gateway-operability` bila sudah diterapkan; verifikasi pencarian audit dan pemeriksaan host sesuai baseline saat implementasi.

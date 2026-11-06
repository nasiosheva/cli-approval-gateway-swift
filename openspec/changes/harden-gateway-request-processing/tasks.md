# Tasks

## 1. Klaim request dan recovery yang aman

- [x] 1.1 Tambahkan lifecycle `requests/` → `processing/` → `processed/` dengan claim rename atomik dan penolakan ID yang sudah memiliki state/response; verifikasi dua watcher yang memperebutkan satu request menghasilkan paling banyak satu approval dan satu eksekusi SSH.
- [x] 1.2 Persist status sebelum memulai SSH dan implementasikan recovery saat startup; verifikasi crash sebelum SSH dan sesudah penanda `ssh-started` tidak menjalankan command ulang otomatis, serta menghasilkan status recovery yang dapat dibaca operator.
- [x] 1.3 Tulis response JSON ke file sementara lalu rename atomik, dan laporkan error baca/audit/response/move dengan ID serta tahapnya; uji kegagalan masing-masing operasi dan pastikan request tidak kembali diam-diam ke pending.
- [x] 1.4 Pertahankan field response yang ada dan tambahkan hanya status yang diperlukan; verifikasi pembaca response lama tetap dapat membaca response sukses, ditolak, dan gagal lokal.
- [x] 1.5 Dokumentasikan status recovery dan prosedur pemeriksaan sebelum retry; verifikasi langkahnya tidak menyuruh memindahkan request berstatus tak diketahui kembali ke antrean.

## 2. Drain output SSH secara paralel

- [x] 2.1 Ubah SSH executor agar membaca stdout dan stderr bersamaan, menutup stdin setelah script terkirim, lalu menunggu proses serta kedua pembaca; verifikasi exit code dan kedua stream tetap terpisah.
- [x] 2.2 Tambahkan stress test subprocess yang menulis lebih dari kapasitas pipe ke stdout dan stderr; verifikasi test selesai tanpa timeout/deadlock dan seluruh output yang dihasilkan muncul pada response.

## 3. Integrasi dan kompatibilitas operasional

- [x] 3.1 Tambahkan uji integrasi lifecycle penuh: approval ditolak, SSH sukses/gagal, penulisan response gagal, dan restart pada setiap batas state; verifikasi setiap ID hanya dapat dieksekusi satu kali otomatis.
- [x] 3.2 Perbarui README dengan direktori `processing/`, perilaku ID duplikat, hasil `execution-unknown`, serta langkah upgrade dan rollback; verifikasi instruksi cocok dengan lifecycle yang diuji.
- [x] 3.3 Build target Debug dan Release dari project Xcode; verifikasi kedua build sukses dan semua file Swift baru ikut terkompilasi.
- [x] 3.4 Jalankan verifikasi manual di sesi Terminal interaktif dengan dua watcher dan output SSH besar; catat hasil approval, response, audit, dan state filesystem tanpa menyertakan secret.

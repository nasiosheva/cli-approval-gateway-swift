# Design

## Context

Lihat proposal untuk alasan dan spec `reliable-request-execution` untuk kontrak perilaku. Saat ini watcher memindai `.sh` langsung dari `requests/`, menjalankan pemrosesan sinkron, mengabaikan beberapa error file dengan `try?`, dan membaca stdout sampai EOF sebelum membaca stderr. Protokol sudah memakai ID request dan direktori `responses/` serta `processed/`.

## Goals / Non-Goals

**Goals:**
- Klaim eksklusif per request ID sebelum approval agar beberapa watcher tidak mengeksekusi request yang sama.
- Jangan menjalankan ulang otomatis command yang status remote-nya tidak diketahui setelah crash.
- Tulis response lengkap secara atomik, pertahankan output stream terpisah, dan tampilkan kegagalan lokal secara eksplisit.
- Drain stdout dan stderr bersamaan.

**Non-Goals:**
- Menjamin exactly-once pada host remote. SSH tidak menyediakan transaksi bersama filesystem lokal; crash atau putus koneksi setelah command dimulai dapat membuat hasil remote tidak diketahui.
- Mengubah sintaks file `.sh`, aturan approval, SSH host config, placeholder Keychain, atau membuat retry otomatis.

## Decisions

### Lifecycle dan claim request

Tambahkan direktori `processing/`. Gateway memindahkan file `.sh` dari `requests/` ke `processing/` dengan rename atomik pada filesystem yang sama sebelum memanggil approval. Hanya proses yang berhasil memindahkan file yang boleh melanjutkan. Tolak atau tandai ID yang sudah ada di `processing/`, `processed/`, atau `responses/` agar ID lama tidak dapat digunakan untuk menjalankan ulang command.

Setelah approval ditolak, gateway menulis response penolakan lalu memindahkan file ke `processed/`. Sebelum memanggil SSH, gateway menyimpan penanda tahap `ssh-started` di status request. Setelah SSH selesai dan result berhasil ditulis, file request dipindahkan ke `processed/`. Error pada claim, status, response, audit, atau finalisasi harus dicatat ke stderr dengan ID dan tahapnya; request yang belum selesai tetap berada di luar `requests/` sehingga tidak dipungut ulang.

**Alternatif:** global single-instance lock saja. Ditolak sebagai satu-satunya mekanisme karena lock mencegah watcher ganda tetapi tidak mencegah replay akibat crash/restart atau request ID yang dipakai ulang. Claim atomik per request tetap diperlukan; lock dapat ditambahkan jika implementasi memerlukan serialisasi global.

### Recovery setelah restart

Pada startup, pindai `processing/` sebelum `requests/`. Request tanpa penanda bahwa SSH dimulai dapat dipindah ke status recovery untuk pemeriksaan operator; jangan jalankan ulang otomatis karena proses mungkin berhenti pada batas antara pencatatan status dan pemanggilan SSH. Request dengan penanda `ssh-started` tanpa response terminal ditandai `execution-unknown` dan tidak dieksekusi ulang. Response memakai field status tambahan bila bisa ditulis; bila penulisan response gagal, log terminal menjelaskan ID dan lokasi status yang harus diperiksa.

Operator memeriksa dampak di server sebelum membuat request baru untuk percobaan ulang. Ini mempertahankan keamanan pada batas yang tidak dapat dibuat atomik lintas proses lokal dan remote.

### Persistensi response dan audit

Tulis JSON ke file sementara di direktori `responses/`, lalu rename atomik ke `<id>.json`. Hanya pindahkan request ke `processed/` setelah response terminal tersimpan. Jika penyimpanan response gagal setelah SSH selesai, simpan request di `processing/` dengan status recovery yang tidak dapat dipindai sebagai pending, keluarkan error ke stderr, dan jangan jalankan command lagi.

Kegagalan audit tidak boleh disembunyikan. Catat error audit ke stderr dan tetap pertahankan response/result bila tersedia; jangan menghapus atau mengantrekan ulang request. Response yang berhasil disimpan tetap menyertakan field lama (`id`, `timestamp`, `host`, `approved`, `exitCode`, `stdout`, `stderr`) agar pembaca yang ada kompatibel; field status baru bersifat tambahan.

**Alternatif:** memindahkan request ke `processed/` sebelum response ditulis. Ditolak karena agent dapat melihat request selesai tanpa hasil yang durable.

### Pembacaan output SSH

Mulai pembacaan stdout dan stderr secara paralel segera setelah proses SSH berjalan, dan tutup stdin setelah script terkirim. Tunggu proses dan kedua pembaca selesai sebelum membentuk `CommandResult`. Pertahankan dua buffer terpisah untuk menjaga bentuk response saat ini.

**Alternatif:** menggabungkan stderr ke stdout. Ditolak karena menghilangkan pembedaan yang saat ini tersedia pada response.

## Risks / Trade-offs

- [Hasil remote tidak pasti setelah koneksi putus atau proses crash] → Tandai `execution-unknown`, jangan retry otomatis, dan minta operator memeriksa server sebelum mengirim request baru.
- [File berstatus recovery memerlukan tindakan manual] → Laporkan ID dan lokasi state secara jelas; dokumentasikan prosedur inspeksi/retry yang memakai ID baru.
- [Output command dapat besar] → Pembaca paralel menghindari deadlock pipe, tetapi buffer tetap memori; batas output bukan bagian dari scope ini.
- [Gateway lama berjalan bersamaan saat upgrade] → Hentikan watcher lama sebelum memasang versi baru; instance lama tidak memahami direktori `processing/`.

## Migration Plan

1. Hentikan semua instance gateway lama sebelum mengganti binary.
2. Versi baru membuat `processing/` bila belum ada dan mempertahankan `requests/`, `responses/`, `processed/`, serta format JSON lama.
3. Request `.sh` yang masih berada di `requests/` diproses dengan lifecycle baru. Jangan menghapus request lama atau state recovery otomatis.
4. Verifikasi dengan dua watcher yang bersaing, crash injection di tiap batas lifecycle, kegagalan tulis, dan output besar pada dua stream.
5. Jika rollback diperlukan, hentikan versi baru sebelum menjalankan binary lama. Jangan memindahkan state `processing/` kembali ke `requests/` secara massal; periksa status remote lebih dahulu untuk mencegah eksekusi ganda.

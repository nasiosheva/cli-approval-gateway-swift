# Tasks

## 1. Timeout eksekusi dan validasi host (execution-safety)

- [ ] 1.1 Tambahkan batas waktu konfigurabel (`GATEWAY_SSH_TIMEOUT_SECONDS`, fallback 120s) pada `SSHExecutor.run`; hentikan proses dan kedua pipe-reader saat timeout tercapai; verifikasi command yang sengaja `sleep` lebih lama dari batas menghasilkan response berstatus `timed-out` dengan output parsial, bukan watcher menggantung.
- [ ] 1.2 Validasi host (dari `#GATEWAY-HOST:` atau default) lewat `ssh -G <host>` sebelum memanggil approval; verifikasi host yang tidak dikenal ditolak dengan status `host-unknown` tanpa memicu dialog Touch ID, dan host yang valid tetap lanjut normal.
- [ ] 1.3 Pastikan request `timed-out` dan `host-unknown` tetap mengikuti jalur finalize (pindah ke `processed/`, response ditulis) seperti status gagal lain; verifikasi tidak ada request yang tersisa di `processing/` setelah kedua skenario ini.

## 2. Rotasi dan pembersihan data (data-retention)

- [ ] 2.1 Tambahkan rotasi `audit.log` berbasis ukuran (ambang dikonfigurasi, fallback 10 MB) di `AuditLogger`; verifikasi file yang melewati ambang di-rotate ke `audit.log.1` dan penulisan berikutnya mulai dari file baru tanpa kehilangan entri yang sudah tercatat.
- [ ] 2.2 Tambahkan subcommand `cli-approval-gateway cleanup --older-than <hari>` yang menghapus pasangan file di `responses/` dan `processed/` lebih tua dari ambang; verifikasi file yang lebih baru dari ambang tidak terhapus, dan dry-run opsional (`--dry-run`) hanya menampilkan daftar tanpa menghapus.
- [ ] 2.3 Dokumentasikan rotasi dan subcommand `cleanup` di README serta `--help`; verifikasi instruksi mencantumkan default ambang dan cara override lewat env/flag.

## 3. Visibilitas operator (operator-visibility)

- [ ] 3.1 Tambahkan heartbeat log singkat di loop utama saat idle melewati ambang waktu (dikonfigurasi, fallback 5 menit); verifikasi watcher yang idle lama tetap mencetak tanda hidup tanpa membanjiri terminal per-detik.
- [ ] 3.2 Tambahkan notifikasi sistem macOS (best-effort, lewat `osascript display notification`) saat request baru diklaim dan akan meminta approval; verifikasi kegagalan notifikasi (misal `osascript` tidak tersedia) tidak menggagalkan pemrosesan request.
- [ ] 3.3 Dokumentasikan heartbeat dan notifikasi di README; verifikasi deskripsi mencocokkan perilaku default dan cara mematikan/override ambang.

## 4. Integrasi dan verifikasi

- [ ] 4.1 Perbarui/tambahkan self-test (`selftest`) untuk skenario timeout SSH dan validasi host, tanpa butuh SSH/Touch ID asli; verifikasi self-test baru lulus bersama self-test yang sudah ada (`ssh-drain`, `lifecycle`).
- [ ] 4.2 Build target Debug dan Release dari project Xcode; verifikasi kedua build sukses dan semua file Swift baru ikut terkompilasi.
- [ ] 4.3 Jalankan verifikasi manual: satu request dengan command yang sengaja lama (timeout), satu request dengan host typo (host-unknown), dan biarkan watcher idle untuk mengamati heartbeat serta notifikasi approval; catat hasil tanpa menyertakan secret.

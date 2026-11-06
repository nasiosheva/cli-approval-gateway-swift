# Design

## Context

Lihat proposal untuk alasan dan spec `execution-safety`, `data-retention`, `operator-visibility` untuk kontrak perilaku. Gateway saat ini memproses request satu per satu secara sinkron di loop utama (`main.swift`), memanggil `SSHExecutor.run` tanpa batas waktu, tidak memvalidasi host sebelum approval, menulis `audit.log` dengan append tanpa batas, dan tidak pernah menghapus `responses/`/`processed/`. Watcher mencetak banyak baris saat start lalu diam total ketika idle.

## Goals / Non-Goals

**Goals:**
- Cegah satu request bermasalah (SSH menggantung) memblokir seluruh antrean selamanya.
- Cegah approval Touch ID terbuang untuk request yang pasti gagal karena host salah ketik.
- Jaga `audit.log`, `responses/`, `processed/` tidak tumbuh tanpa batas.
- Beri operator sinyal yang jelas bahwa watcher hidup (idle) dan bahwa ada approval yang menunggu, tanpa harus memantau terminal terus-menerus.

**Non-Goals:**
- Memproses beberapa request secara konkuren (tetap satu per satu; timeout hanya membatasi durasi satu request, bukan mengubah model konkurensi).
- Retry otomatis untuk request yang timeout atau host-nya tidak dikenal — tetap perlu request baru dengan ID baru, konsisten dengan kebijakan `execution-unknown` yang sudah ada.
- Mengubah mekanisme approval itu sendiri (Touch ID/Face ID) atau cara `#GATEWAY-HOST:` ditulis di file request.

## Decisions

### Timeout eksekusi SSH

`SSHExecutor.run` menerima batas waktu (default dikonfigurasi lewat env, misalnya `GATEWAY_SSH_TIMEOUT_SECONDS`, fallback 120 detik). Thread yang menunggu `process.waitUntilExit()` dibatasi lewat `DispatchSemaphore.wait(timeout:)`; kalau timeout tercapai, proses SSH di-`terminate()`, kedua pipe-reader thread yang masih jalan dihentikan, dan hasil dikembalikan dengan status `timed-out` berisi output yang sempat diterima sampai saat itu. Request yang timeout tetap mengikuti jalur finalize normal (pindah ke `processed/`, response ditulis), bukan dibiarkan menggantung di `processing/` — ini konsisten dengan prinsip "tidak ada request yang diam-diam tetap pending" dari perubahan sebelumnya.

**Alternatif:** biarkan operator membunuh watcher manual saat macet (perilaku saat ini). Ditolak karena ini justru insiden yang sudah pernah terjadi dan memblokir seluruh queue, bukan hanya satu request.

### Validasi host sebelum approval

Sebelum memanggil `gate.approve(...)`, gateway menjalankan `ssh -G <host>` (menampilkan konfigurasi resolved tanpa connect) untuk memastikan host dikenal di `~/.ssh/config` atau merupakan hostname/IP yang valid secara sintaksis. Kalau tidak dikenal, request ditolak dengan status `host-unknown` tanpa pernah memicu dialog Touch ID.

**Alternatif:** validasi dengan benar-benar mencoba `ssh` connect dulu. Ditolak karena connect sungguhan bisa lambat/menggantung juga (perlu timeout sendiri) dan mengubah command yang dikirim; `ssh -G` cukup untuk mendeteksi typo tanpa side effect jaringan.

### Rotasi audit log dan cleanup

`AuditLogger` memeriksa ukuran file sebelum append; kalau melebihi ambang (misal 10 MB), file lama di-rename ke `audit.log.1` (menimpa rotasi sebelumnya kalau ada) sebelum menulis entri baru ke file kosong. Subcommand baru `cli-approval-gateway cleanup --older-than <hari>` memindai `responses/` dan `processed/`, menghapus pasangan file yang lebih tua dari ambang; hanya berjalan saat dipanggil manual oleh operator, tidak otomatis di dalam loop watcher (supaya tidak ada penghapusan data yang tidak diminta saat watcher jalan tanpa pengawasan).

**Alternatif:** cleanup otomatis berjalan di background thread watcher. Ditolak untuk fase ini karena penghapusan data sebaiknya eksplisit atas inisiatif operator, bukan otomatis diam-diam.

### Heartbeat dan notifikasi

Loop utama mencatat waktu poll terakhir yang mencetak sesuatu; kalau sudah idle lebih dari ambang (misal 5 menit), cetak satu baris heartbeat singkat (`[idle] menunggu request... (<timestamp>)`) lalu reset penghitung — bukan tiap iterasi poll, supaya tidak membanjiri terminal. Saat request baru diklaim dan akan meminta approval, panggil `osascript -e 'display notification ...'` (lewat helper kecil, best-effort — kegagalan notifikasi tidak boleh menggagalkan pemrosesan request).

**Alternatif:** pakai framework `UserNotifications` native. Ditolak untuk sekarang karena butuh bundle/signing app yang lebih berat; `osascript display notification` cukup untuk CLI tanpa app bundle penuh.

## Migration Plan

Tidak ada migrasi data. Env var baru (`GATEWAY_SSH_TIMEOUT_SECONDS`) bersifat opsional dengan fallback yang masuk akal. Status response baru (`timed-out`, `host-unknown`) adalah tambahan field `status`, tidak mengubah field yang sudah ada — pembaca response lama yang hanya cek `approved`/`exitCode` tidak perlu berubah.

## Open Questions

- Ambang timeout default (120 detik) dan ambang idle heartbeat (5 menit) perlu dikonfirmasi ke operator sebelum implementasi — bisa disesuaikan lewat env var kalau defaultnya kurang pas untuk command yang memang biasa lama.

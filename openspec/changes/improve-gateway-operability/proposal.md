# Proposal

## Why

Gateway yang sudah berjalan (hasil `harden-gateway-request-processing`) aman dari duplikasi dan deadlock pipe, tetapi masih punya risiko operasional yang belum ditangani: command SSH yang menggantung (misalnya menunggu host-key prompt atau koneksi lambat) memblokir seluruh antrean karena pemrosesan masih satu per satu; host tujuan yang salah ketik baru ketahuan gagal setelah operator sudah memberi approval Touch ID; `audit.log`, `responses/`, dan `processed/` tidak pernah dibersihkan sehingga tumbuh tanpa batas; dan operator tidak mendapat tanda apa pun saat ada request yang menunggu approval atau saat watcher masih hidup dalam keadaan idle, sehingga mudah mengira watcher macet padahal sedang menunggu.

## What Changes

- Tambahkan timeout keras pada eksekusi SSH per request; command yang melewati batas waktu ditandai `timed-out` di response, bukan membuat watcher menggantung tanpa batas.
- Validasi host target (dari `#GATEWAY-HOST:` atau default) terhadap daftar alias SSH yang dikenal (`~/.ssh/config`) sebelum meminta approval, supaya typo host tidak membuang approval Touch ID untuk request yang pasti gagal.
- Tambahkan rotasi `audit.log` berbasis ukuran file, dan subcommand `cleanup` untuk menghapus entri lama di `responses/` dan `processed/` berdasarkan umur file.
- Cetak baris heartbeat singkat secara periodik saat watcher idle, dan kirim notifikasi sistem macOS saat request baru menunggu approval.

## Capabilities

### New Capabilities
- `execution-safety`: batas waktu eksekusi SSH dan validasi host sebelum approval diminta.
- `data-retention`: rotasi audit log dan pembersihan terjadwal untuk `responses/`/`processed/`.
- `operator-visibility`: heartbeat log saat idle dan notifikasi sistem saat ada approval tertunda.

### Modified Capabilities

## Impact

Perubahan menyentuh `SSHExecutor.swift` (timeout), `RequestProcessor.swift`/`main.swift` (validasi host, heartbeat, pemanggilan notifikasi), `AuditLog.swift` (rotasi), dan file baru untuk notifikasi sistem serta subcommand `cleanup`. Tidak mengubah format response JSON yang sudah ada selain menambah nilai `status` baru (`timed-out`, `host-unknown`), tidak mengubah protokol klaim/recovery, autentikasi SSH, atau skema bundle password.

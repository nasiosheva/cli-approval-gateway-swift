# Proposal: Refactor modularisasi + hilangkan hardcode

## Alasan

`main.swift` saat ini berisi SEMUA tanggung jawab gateway dalam satu file
(~650+ baris): konfigurasi, audit log, approval gate, secret store
(Keychain), resolusi placeholder password, eksekusi SSH, pemrosesan
request, subcommand `pw`, dan entry point/loop watcher. Ini sudah mulai
sulit dinavigasi dan diubah dengan aman — setiap perubahan kecil (seperti
menambah dukungan multi-server kemarin) butuh menyusuri satu file panjang
dan rawan merusak bagian lain yang tidak terkait.

Selain itu beberapa nilai konfigurasi masih ditulis langsung di kode
(hardcoded) padahal secara konsep adalah setting yang masuk akal untuk
dikonfigurasi lewat environment variable, bukan baris kode:

- Default SSH host `"pe-server"` (sudah bisa di-override lewat
  `GATEWAY_SSH_HOST`, tapi default-nya tertulis literal di
  `GatewayConfig.load()`).
- Nama folder base `.cli-approval-gateway` (literal string di
  `GatewayConfig.load()`).
- Nama service Keychain `"com.cli-approval-gateway.secrets"` (literal
  string di `SecretStore`).
- Interval polling watcher `1.0` detik (literal di `GatewayConfig.load()`).

## Tujuan

1. Pecah `main.swift` menjadi beberapa file Swift per tanggung jawab,
   masing-masing dengan satu fokus jelas, supaya mudah dibaca, diuji, dan
   diubah tanpa menyentuh bagian lain yang tidak terkait.
2. Pindahkan nilai-nilai yang disebut di atas ke satu tempat terpusat
   (`GatewayConfig`) yang SEMUA bisa dioverride lewat environment
   variable, dengan default yang didokumentasikan jelas di satu lokasi
   (bukan tersebar).
3. **Tidak ada perubahan behavior** — ini refactor murni (pecah file +
   hilangkan hardcode), bukan menambah/menghapus fitur. Semua yang sudah
   terverifikasi bekerja (approval Touch ID, SSH exec, placeholder
   password, multi-server, `pw add/edit/show/list/reveal/remove`) harus
   tetap bekerja persis sama setelah refactor.

## Scope

- **Termasuk**: pemecahan file, ekstraksi konstanta/default ke
  `GatewayConfig` + environment variable, penyesuaian target Xcode agar
  semua file baru ikut dikompilasi.
- **Tidak termasuk**: fitur baru, perubahan desain approval/Keychain,
  perubahan protokol file-based IPC (`requests/`/`responses/`/
  `processed/`), perubahan `pw` subcommand behavior.

## Dampak

- Tidak ada dampak ke operator/agent yang memakai gateway — command CLI
  (`pw ...`, file-based IPC `requests/`) tetap sama persis.
- Risiko utama: regresi tidak sengaja saat memindah kode antar file
  (misalnya urutan inisialisasi global di entry point, atau akses
  `private` yang berubah makna saat lintas file). Dimitigasi lewat build
  + uji ulang skenario inti (lihat `tasks.md`) sebelum dianggap selesai.

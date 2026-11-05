# Proposal

## Why

- Pola kerja deploy/operasi server saat ini: agent (Claude Code atau agent
  lain) menyarankan command, operator menjalankan sendiri di terminal, lalu
  mengetik ulang hasilnya ke agent. Round-trip ini lambat dan terasa
  manual.
- Operator ingin eksekusi tetap **manual** (butuh persetujuan eksplisit per
  command, tidak auto-trigger) tapi **tidak terasa manual** — agent cukup
  minta command dijalankan dan langsung menerima response nyata
  (stdout/stderr/exit code), tanpa operator mengetik ulang hasil.
- Cakupan yang diinginkan lebih luas dari satu agent: agent/LLM apa pun
  (termasuk vendor lain yang tidak punya mekanisme permission-prompt
  seperti Claude Code) harus bisa memakai mekanisme yang sama.
- Constraint keras yang disepakati di awal diskusi:
  - Password (sudo, DB, dll) tidak boleh diketik ke chat/percakapan dengan
    agent manapun (akan tersimpan permanen di log percakapan).
  - Password tidak boleh hardcode di file/script yang bisa ikut
    ter-commit ke repository manapun.
  - Semua tetap berjalan lokal di mesin operator — tidak ada service
    cloud/network eksternal yang ikut memegang credential.
- Opsi yang dipertimbangkan dan ditolak sebelum sampai ke desain ini:
  mematikan seluruh permission-prompt (full-auto), atau CLI yang menyimpan
  password dan menjalankan command bebas tanpa approval per-panggilan.
  Keduanya ditolak karena menghilangkan satu-satunya pengaman command
  salah/halusinasi/prompt-injection langsung tereksekusi sebagai root di
  server production sistem pemerintahan.

## What Changes

- Bangun aplikasi command-line macOS (Swift) `cli-approval-gateway` yang
  berjalan sebagai proses watcher lokal:
  - Memantau folder `~/.cli-approval-gateway/requests/` untuk file
    `<id>.sh` berisi command yang diminta agent.
  - Menampilkan isi command (mentah, tanpa substitusi password) ke
    terminal dan meminta approval **Touch ID/Face ID** sebelum eksekusi
    apa pun.
  - Setelah disetujui, mengirim command ke server target lewat
    `ssh <host> bash -s` (command dikirim sebagai stdin, bukan file yang
    ditulis ke remote), menangkap stdout/stderr/exit code.
  - Menulis hasil ke `responses/<id>.json` supaya agent bisa membaca
    response nyata tanpa operator mengetik ulang.
  - Mencatat setiap transaksi (approved maupun ditolak) ke `audit.log`
    sebagai JSON Lines, append-only.
- Tambah subcommand `pw` untuk menyimpan password per tag di **macOS
  Keychain** (bukan file plaintext): `pw add <tag>`, `pw list`,
  `pw remove <tag>`. Setiap tag dilindungi Touch ID/Face ID terpisah saat
  diambil (`SecAccessControl` `.userPresence`).
- Tambah mekanisme placeholder `{{pw:<tag>}}` di isi command — gateway
  mengganti placeholder dengan nilai asli dari Keychain hanya di memory,
  tepat sebelum dikirim ke SSH stdin. Command mentah (dengan placeholder,
  bukan nilai asli) yang selalu ditampilkan ke terminal dan ditulis ke
  audit log.
- Mulai memakai struktur OpenSpec (`docs/changes/<slug>/`) untuk project
  ini, mengikuti konvensi yang sudah dipakai di repo BE
  `apiperjanjiankerjasama-main`, supaya perubahan berikutnya tetap punya
  proposal, spec, design, dan tasks yang bisa diverifikasi.

## Capabilities

### New Capabilities

- `approval-gateway-watcher`: proses watcher lokal yang menerima permintaan
  eksekusi command dari agent manapun lewat file-based IPC
  (`requests/*.sh` → `responses/*.json`), dengan gate approval Touch
  ID/Face ID wajib sebelum eksekusi apa pun ke server lewat SSH.
- `tagged-secret-store`: penyimpanan password bertag di macOS Keychain
  (`pw add/list/remove`) dengan access control biometrik per-item, plus
  substitusi `{{pw:tag}}` in-memory saat eksekusi command.

## Impact

- Kode baru seluruhnya berada di `cli-approval-gateway/main.swift` (single
  file untuk v1) dan project Xcode
  `cli-approval-gateway.xcodeproj` di repo ini — tidak menyentuh repo
  `apiperjanjiankerjasama-main` (BE) maupun repo FE sama sekali.
- Tidak ada perubahan skema database, API, atau kode aplikasi BE/FE.
  Gateway ini murni alat operasional lokal yang memanggil `ssh` ke server
  yang sudah ada; command yang dikirimkannya bisa berupa command apa pun
  yang biasanya dijalankan manual oleh operator (termasuk script deploy
  BE/FE yang sudah ada), tapi gateway ini sendiri tidak mengubah script
  atau pipeline tersebut.
- Risiko utama (lihat `design.md`): command bebas + approval manusia
  berarti blast radius tiap aksi tetap seluas command yang diketik agent —
  mitigasinya murni proses (operator membaca isi command sebelum approve
  Touch ID), bukan pembatasan command di level kode pada v1 ini.

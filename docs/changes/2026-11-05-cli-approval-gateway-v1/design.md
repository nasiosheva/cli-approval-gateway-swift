# Design

## Context

- Project baru, berdiri sendiri di luar repo `apiperjanjiankerjasama-main`
  (BE) dan repo FE. Belum menjadi git repository pada saat proposal ini
  ditulis.
- Target platform: macOS (alasan pemilihan Swift: operator memakai macOS
  dan ingin approval native lewat Touch ID/Face ID via `LocalAuthentication`,
  bukan sekadar y/n di terminal).
- Server target dioperasikan lewat alias SSH `pe-server` yang sudah
  dikonfigurasi di `~/.ssh/config` operator (lihat `CLAUDE.md` repo BE,
  bagian "Akses SSH Server") — gateway ini TIDAK menyimpan/memegang host
  key atau private key sendiri, hanya memanggil binary `ssh` sistem yang
  memakai config yang sudah ada.
- Alternatif yang ditimbang dan ditolak sebelum desain ini (dicatat juga di
  `personal-docs/ide-cli-approval-gateway-deploy-2026-11-05.md` repo BE):
  1. Mematikan seluruh permission-prompt (full-auto) — ditolak, menghapus
     satu-satunya pengaman command salah/halusinasi/prompt-injection
     langsung eksekusi root.
  2. CLI yang menyimpan password dan menjalankan command bebas tanpa
     approval per-panggilan — ditolak, risikonya setara `NOPASSWD` sudoers
     global begitu sesi "unlock".
  3. `NOPASSWD` sudoers di-scope ke satu script tertentu — lebih aman dari
     1/2, tapi tetap berarti kompromise SSH key/akun = eksekusi root tanpa
     password untuk script itu. Tidak dipakai karena operator memilih
     pendekatan approval-per-panggilan yang generik untuk semua agent,
     bukan scoping di level OS.

## Keputusan Desain

### 1. Transport request/response: file-based IPC, bukan network API

Dipilih folder `requests/` → `responses/` (polling 1 detik) dibanding HTTP
API lokal, karena:
- Tidak perlu membuka port apa pun di localhost (permukaan serang lebih
  kecil).
- Agent apa pun yang bisa menulis file lokal (termasuk Claude Code lewat
  Bash tool) otomatis compatible, tanpa perlu library HTTP client khusus.
- Tradeoff: polling 1 detik menambah latensi kecil (maks ~1 detik) dan
  memakai sedikit CPU terus-menerus dibanding `FSEvents`/`DispatchSource`
  yang event-driven. Diterima untuk v1; lihat Open Questions.

### 2. Gate approval: Touch ID/Face ID via LocalAuthentication, bukan y/n

`LAContext.evaluatePolicy(.deviceOwnerAuthentication)` dipilih supaya:
- Tidak ada password yang diketik ke mana pun saat approve command biasa.
- UX cepat (approve dengan sentuhan/wajah) sehingga operator tidak
  tergoda mematikan gate ini demi kecepatan.
- Fallback otomatis ke password device bawaan macOS kalau biometrik
  gagal/tidak tersedia — bukan gateway yang menangani password device,
  itu ditangani sepenuhnya oleh dialog sistem macOS.

### 3. Command tetap bebas, bukan daftar aksi tetap

Operator secara eksplisit memilih command bebas (bukan menu aksi
terbatas), dengan alasan command perlu adaptif sesuai kondisi — fixed
script dianggap terlalu flat. Konsekuensinya: blast radius tiap approval
tetap seluas isi command yang ditulis agent. Mitigasi di v1 ini murni
proses (operator WAJIB membaca isi command yang ditampilkan di terminal
sebelum approve Touch ID), bukan pembatasan command di level kode. Lihat
Open Questions untuk kemungkinan lapisan tambahan (daftar pola yang
ditolak otomatis).

### 4. Password store: macOS Keychain per tag, bukan file

- Setiap tag = satu generic password item (`kSecClassGenericPassword`)
  dengan `kSecAttrService = "com.cli-approval-gateway.secrets"` dan
  `kSecAttrAccount = <tag>`.
- Ditolak: menyimpan password di file (`.env`, `.my.cnf` yang dikelola
  gateway, dsb) — Keychain dipilih karena dienkripsi oleh OS dan terikat
  ke akun login macOS operator, tanpa gateway perlu implementasi
  enkripsi sendiri.
- **Revisi dari rencana awal (setelah uji live 2026-11-05)**: desain awal
  memasang `SecAccessControl` flag `.userPresence` di item Keychain supaya
  Touch ID/Face ID dipaksa oleh ACL Keychain sendiri saat `resolve`. Ini
  GAGAL di uji nyata dengan error `"A required entitlement is not
  present."` — `SecAccessControl` butuh entitlement keychain-access-groups
  yang hanya tersedia untuk binary signed dengan Team ID penuh (Apple
  Developer Program), sedangkan binary ini ad-hoc signed
  (`CODE_SIGN_STYLE = Automatic` tanpa `DEVELOPMENT_TEAM`). Mencoba set
  `DEVELOPMENT_TEAM` ke identity development yang ada juga gagal karena
  `xcodebuild` butuh sertifikat "Mac Development" yang tidak tersedia di
  keychain sistem operator.
  **Keputusan akhir**: item Keychain disimpan tanpa access control
  (`kSecAttrAccessible = WhenUnlockedThisDeviceOnly` saja). Gate Touch
  ID/Face ID dipindah ke level kode: `SecretStore.resolve()` menerima
  `ApprovalGate` dan memanggil `gate.approve(reason:)` sendiri sebelum
  `SecItemCopyMatching` — jadi tetap wajib Touch ID/Face ID untuk
  mengambil nilai password, hanya saja dipaksa oleh kode gateway, bukan
  oleh ACL OS. Properti keamanan yang terlihat operator sama; yang
  berubah hanya siapa yang menegakkannya.

### 5. Substitusi password: placeholder, in-memory, tidak pernah di-log

- Command mentah (dengan placeholder `{{pw:tag}}` apa adanya) adalah satu-
  satunya representasi yang ditampilkan ke terminal dan ditulis ke
  `audit.log`.
- Substitusi ke nilai asli hanya terjadi di variable lokal Swift
  (`resolvedCommand`), tepat sebelum ditulis ke `stdin` proses `ssh`, dan
  variable itu tidak pernah ditulis ke disk oleh gateway.
- Risiko residual yang BELUM ditangani v1: command remote itu sendiri bisa
  saja menulis password ke log/file di SISI SERVER (misalnya kalau script
  remote melakukan `echo $1 > some.log`) — ini di luar kendali gateway;
  tetap tanggung jawab operator untuk memastikan command remote tidak
  membocorkan argumen sensitif.

## Risiko dan Mitigasi

| Risiko | Mitigasi saat ini | Residual |
|---|---|---|
| Command salah/berbahaya di-approve tanpa dibaca teliti | Isi command selalu ditampilkan penuh ke terminal sebelum dialog Touch ID muncul | Bergantung penuh pada kedisiplinan operator membaca; tidak ada auto-block pattern berbahaya di v1 |
| Proses gateway disusupi (malware lokal) selagi berjalan | Approval Touch ID tetap wajib per request — malware tidak otomatis dapat eksekusi tanpa sentuhan fisik operator | Kalau malware bisa mensimulasikan input Touch ID (serangan lanjutan di level OS), mitigasi ini tidak berlaku; di luar scope gateway |
| Password tag salah ketik / tag tidak ada | `resolve()` melempar error, request dibatalkan, response mencatat pesan error | - |
| Audit log bisa dihapus/diedit oleh siapa pun yang punya akses file | Belum ada proteksi; `audit.log` adalah file biasa di `~/.cli-approval-gateway/` | Perlu dipertimbangkan permission file lebih ketat atau rotasi+backup di iterasi berikutnya |
| Gateway tidak berjalan di background (harus dibuka manual) | Operator menjalankan manual lewat Xcode/binary saat dibutuhkan | Request yang masuk saat gateway tidak jalan akan menumpuk di `requests/` tanpa response sampai gateway dijalankan lagi |

## Rollback

- Karena ini aplikasi baru yang berjalan terpisah (bukan mengubah service
  yang sudah ada), "rollback" berarti: hentikan proses gateway (Ctrl-C),
  dan/atau hapus folder `~/.cli-approval-gateway/` beserta tag di Keychain
  (`cli-approval-gateway pw remove <tag>` untuk masing-masing tag, atau
  hapus manual lewat Keychain Access.app dengan mencari service
  `com.cli-approval-gateway.secrets`).
- Tidak ada perubahan permanen ke server (`pe-server`) yang dibuat oleh
  gateway itu sendiri — command apa pun yang dieksekusi ke server adalah
  tanggung jawab command tersebut (sama seperti kalau operator menjalankan
  manual), bukan sesuatu yang perlu di-rollback khusus untuk gateway-nya.

## Open Questions

1. Mekanisme identitas/otorisasi per-agent — human-approval (Touch ID)
   saat ini satu-satunya gate; belum ada token/identity per agent yang
   menulis ke `requests/`.
2. Perlu/tidak daftar pola command yang ditolak otomatis sebelum approval
   (`rm -rf /`, `DROP DATABASE`, dll) sebagai lapisan tambahan.
3. Watcher masih polling 1 detik; pertimbangkan `FSEvents`/`DispatchSource`
   kalau perlu latensi lebih rendah atau efisiensi CPU lebih baik.
4. Belum ada mekanisme supaya proses tetap hidup di background (menu bar
   app atau `launchd` agent) — saat ini harus dijalankan manual dan
   dibiarkan terbuka.
5. Belum ada timeout approval otomatis (auto-deny setelah N menit tanpa
   respons operator).
6. Proteksi `audit.log` (permission file, rotasi, backup) belum dirancang.

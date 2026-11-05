# CLI Approval Gateway

CLI Approval Gateway adalah aplikasi command-line macOS yang menerima permintaan command dari agent melalui file lokal, meminta autentikasi pemilik perangkat, dan menjalankan command yang disetujui pada server melalui SSH. Hasil eksekusi disimpan sebagai JSON agar agent dapat membacanya.

Gateway juga menyediakan penyimpanan password bertag di macOS Keychain dan substitusi placeholder saat command disiapkan untuk SSH. Proyek ini masih dalam pengembangan; tinjau batasan keamanan di bawah sebelum menggunakannya untuk sistem penting.

## Persyaratan

- macOS dengan Xcode dan command-line tools terpasang.
- Autentikasi pemilik perangkat macOS yang dapat digunakan oleh LocalAuthentication.
- SSH yang sudah dikonfigurasi untuk host tujuan, termasuk akses ke `bash` di server. Gateway menjalankan `/usr/bin/ssh <host> bash -s` dan mengirim script melalui stdin; siapkan autentikasi SSH yang sesuai untuk operasi noninteraktif.

## Build dan instalasi

Di direktori proyek, build binary dengan:

```bash
xcodebuild -project cli-approval-gateway.xcodeproj \
  -scheme cli-approval-gateway -configuration Debug \
  -derivedDataPath build build
```

Opsional, salin binary ke lokasi tetap agar dapat digunakan dari direktori mana pun:

```bash
mkdir -p "$HOME/.cli-approval-gateway/bin"
cp build/Build/Products/Debug/cli-approval-gateway \
  "$HOME/.cli-approval-gateway/bin/cli-approval-gateway"
```

Tambahkan folder tersebut ke `PATH` di `~/.zshrc`, kemudian jalankan `source ~/.zshrc`:

```zsh
export PATH="$HOME/.cli-approval-gateway/bin:$PATH"
```

Setelah kode diubah dan di-build ulang, salin kembali binary jika menggunakan lokasi tetap tersebut.

## Menjalankan gateway

Jalankan watcher di terminal operator:

```bash
GATEWAY_SSH_HOST=nama-host-ssh cli-approval-gateway
```

`GATEWAY_SSH_HOST` menentukan host default; jika tidak diisi, kode menggunakan `pe-server`. Watcher berjalan di foreground. Biarkan terminal terbuka selama digunakan, lalu tekan `Ctrl+C` untuk menghentikannya. Gateway tidak dikonfigurasi untuk berjalan otomatis saat login.

| Environment variable | Default | Fungsi |
| --- | --- | --- |
| `GATEWAY_SSH_HOST` | `pe-server` | Host SSH default. |
| `GATEWAY_BASE_DIR_NAME` | `.cli-approval-gateway` | Nama direktori data di bawah home. |
| `GATEWAY_POLL_INTERVAL_SECONDS` | `1.0` | Interval polling positif dalam detik; nilai tidak valid memakai default. |
| `GATEWAY_KEYCHAIN_SERVICE_NAME` | `com.cli-approval-gateway.secrets` | Nama service Keychain. Mengubahnya membuat tag pada service lama tidak terlihat sampai nama semula digunakan kembali. |

Saat dimulai, gateway membuat direktori berikut di `~/.cli-approval-gateway/`:

| Lokasi | Fungsi |
| --- | --- |
| `requests/` | File request `<id>.sh` yang menunggu diproses. |
| `responses/` | Hasil `<id>.json` untuk setiap request. |
| `processed/` | File request yang sudah diproses. |
| `audit.log` | Catatan transaksi dalam format JSON Lines. |

## Membuat request

Gunakan ID yang unik. Tulis file sementara di direktori yang sama, kemudian pindahkan ke nama `.sh` agar watcher tidak membaca file yang belum selesai ditulis:

```bash
id="$(uuidgen)"
dir="$HOME/.cli-approval-gateway"
printf '%s\n' 'hostname && whoami && date' > "$dir/requests/$id.tmp"
mv "$dir/requests/$id.tmp" "$dir/requests/$id.sh"
echo "Request: $id"
```

Gateway menampilkan host dan command mentah di terminal operator, lalu meminta autentikasi. Setelah diproses, baca `responses/<id>.json`. Respons memuat `id`, `timestamp`, `host`, `approved`, `exitCode`, `stdout`, dan `stderr`. `approved: true` berarti autentikasi request berhasil, bukan jaminan command berhasil: periksa juga `exitCode` dan `stderr`. Jika request ditolak atau resolusi password gagal, `exitCode` bernilai `null` dan SSH tidak dijalankan.

Untuk memilih host berbeda pada satu request, tempatkan directive berikut **pada baris pertama** file:

```bash
#GATEWAY-HOST: nama-host-ssh-lain
hostname
```

Host dapat berupa alias yang dikenal konfigurasi SSH. Tanpa directive, gateway menggunakan host default. Directive tetap menjadi komentar dalam script yang dikirim ke server.

## Mengelola password

Jalankan perintah berikut di terminal operator. Input password untuk `add` dan `edit` tidak ditampilkan saat diketik.

```bash
cli-approval-gateway pw add sudo       # tambah atau ganti nilai
cli-approval-gateway pw edit sudo      # alias add
cli-approval-gateway pw list           # hanya nama tag
cli-approval-gateway pw show sudo      # periksa apakah tag ada
cli-approval-gateway pw reveal sudo    # tampilkan nilai setelah autentikasi
cli-approval-gateway pw remove sudo    # hapus tag
cli-approval-gateway pw delete sudo    # alias remove
```

`reveal` mencetak password ke stdout: gunakan hanya secara langsung oleh operator di terminal yang aman, bukan melalui tool agent atau di chat. `add` dan `edit` mengganti nilai tag yang sudah ada.

### Placeholder dan password per host

Gunakan `{{pw:tag}}` dalam file request; gateway menggantinya di memori setelah autentikasi dan sebelum mengirim script ke SSH. Nama tag dalam placeholder mendukung huruf, angka, `_`, dan `-`. Untuk request ke `server-2`, placeholder `{{pw:sudo}}` terlebih dahulu mencari tag `sudo@server-2`, lalu menggunakan `sudo` jika tag khusus host tidak ditemukan. Simpan nilai khusus host misalnya dengan:

```bash
cli-approval-gateway pw add 'sudo@server-2'
```

Substitusi adalah penggantian teks mentah, bukan escaping shell. Karakter khusus dalam password dapat mengubah sintaks atau perilaku script. Command yang mencetak atau menyimpan password juga dapat membocorkannya melalui output, server, atau file respons; rancang dan tinjau command dengan hati-hati.

## Integrasi agent

Agent yang memiliki akses ke folder gateway dapat membuat request dan membaca respons menggunakan protokol file di atas. Instruksi yang dapat ditambahkan ke konfigurasi agent:

1. Pastikan operator sudah menjalankan watcher dan gunakan ID unik untuk setiap request.
2. Tulis script ke file sementara di `requests/`, lalu pindahkan menjadi `<id>.sh`.
3. Tunggu dan baca `responses/<id>.json`; periksa status approval, exit code, dan output.
4. Gunakan placeholder untuk password; jangan meminta password asli di chat atau menjalankan `pw reveal` melalui agent.

Gateway tidak menyediakan identitas atau otorisasi khusus per agent; akses ke folder dan izin sistem operasi menentukan siapa yang dapat membuat request dan membaca respons. Jangan menganggap output command otomatis bebas dari data sensitif.

## Keamanan dan batasan

- Baca command dan host yang ditampilkan sebelum menyetujui. Gateway tidak membatasi jenis command yang dapat dijalankan setelah disetujui.
- Autentikasi menggunakan kebijakan `deviceOwnerAuthentication` macOS, yang dapat menggunakan password perangkat sebagai fallback. Dialog tidak selalu muncul untuk setiap operasi, bergantung pada perilaku autentikasi macOS.
- Item Keychain tidak memiliki ACL biometrik khusus; pemeriksaan autentikasi sebelum pengambilan password diterapkan dalam kode gateway. Jangan menganggapnya sebagai perlindungan biometrik yang dipaksakan langsung oleh Keychain terhadap semua akses lain.
- Audit menyimpan command mentah termasuk placeholder, bukan hasil substitusi. Namun output server disimpan dalam respons dan dapat mengandung informasi sensitif. Jangan menaruh password asli dalam request.
- Watcher memproses request secara berurutan dan belum menyediakan timeout approval, rotasi audit, atau pembatasan command. Hak akses folder, keamanan SSH, dan penanganan data di server tetap menjadi tanggung jawab operator.

## Struktur proyek

- `cli-approval-gateway/` — entry point dan modul konfigurasi, autentikasi, Keychain, SSH, serta pemrosesan request.
- `cli-approval-gateway.xcodeproj/` — proyek Xcode.
- `docs/changes/` — proposal, desain, spesifikasi, dan catatan tugas.
- `personal-docs/` — catatan operasional lokal yang dikecualikan dari Git.

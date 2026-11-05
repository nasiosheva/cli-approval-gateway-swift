# Capability: approval-gateway-watcher + tagged-secret-store

## Context

Gateway lokal (Swift CLI/daemon, macOS) yang menjembatani agent (Claude
Code atau agent/LLM lain) dengan eksekusi command nyata di server lewat
SSH, dengan gate persetujuan manusia (Touch ID/Face ID) sebelum eksekusi
apa pun, dan penyimpanan password bertag di macOS Keychain supaya
credential tidak pernah lewat chat/agent atau hardcode di file.

## Requirements

### Requirement: Watcher memproses request secara eksklusif dan berurutan

Gateway HARUS memantau folder `requests/` dan memproses setiap file
`<id>.sh` tepat satu kali.

#### Scenario: File request baru muncul

- **WHEN** sebuah file `<id>.sh` baru muncul di folder `requests/`
- **THEN** gateway membacanya, menampilkan isi mentahnya ke terminal, dan
  meminta approval sebelum eksekusi apa pun

#### Scenario: File yang sudah diproses tidak dieksekusi ulang

- **WHEN** sebuah file `<id>.sh` sudah selesai diproses (approved maupun
  ditolak)
- **THEN** gateway memindahkan file tersebut ke folder `processed/`
  sehingga tidak terbaca lagi oleh loop watcher berikutnya

### Requirement: Eksekusi command wajib melalui approval biometrik

Gateway TIDAK BOLEH mengeksekusi command apa pun ke server tanpa
persetujuan Touch ID/Face ID (atau fallback password device bawaan
sistem) dari operator untuk request tersebut.

#### Scenario: Operator menyetujui lewat Touch ID/Face ID

- **WHEN** operator berhasil approve dialog biometrik untuk suatu request
- **THEN** gateway mengirim command ke host target lewat SSH dan menulis
  hasil eksekusi (exit code, stdout, stderr) ke `responses/<id>.json`

#### Scenario: Operator menolak atau approval gagal

- **WHEN** operator membatalkan dialog atau approval gagal/tidak tersedia
- **THEN** gateway TIDAK mengeksekusi command apa pun, dan menulis
  response dengan `approved: false` serta `exitCode: null`

### Requirement: Command mentah tidak pernah berisi nilai password asli di log/terminal

Representasi command yang ditampilkan ke terminal dan yang ditulis ke
`audit.log` HARUS selalu versi mentah (placeholder `{{pw:tag}}` apa
adanya), tidak pernah versi dengan password sudah disubstitusi.

#### Scenario: Command memuat placeholder password

- **WHEN** isi command request memuat `{{pw:<tag>}}`
- **THEN** banner terminal dan entri `audit.log` untuk request tersebut
  menampilkan teks `{{pw:<tag>}}` secara literal, bukan nilai password
  asli

#### Scenario: Substitusi password hanya terjadi tepat sebelum eksekusi

- **WHEN** request sudah disetujui dan command memuat satu atau lebih
  placeholder `{{pw:tag}}`
- **THEN** gateway mengambil nilai asli dari Keychain in-memory, mengganti
  placeholder, dan mengirim hasil substitusi hanya ke stdin proses `ssh` —
  nilai asli tidak pernah ditulis ke file apa pun oleh gateway

### Requirement: Password per tag disimpan di Keychain, bukan file

Subcommand `pw` HARUS menyimpan, mendaftar, dan menghapus password lewat
macOS Keychain API (`Security` framework), dengan satu tag memetakan ke
satu account Keychain.

#### Scenario: Menambah password baru dengan tag

- **WHEN** operator menjalankan `cli-approval-gateway pw add <tag>` dan
  mengetik password
- **THEN** input tidak di-echo ke terminal, dan password tersimpan di
  Keychain dengan access control yang mewajibkan Touch ID/Face ID
  (`.userPresence`) untuk pengambilan berikutnya

#### Scenario: Menampilkan daftar tag

- **WHEN** operator menjalankan `cli-approval-gateway pw list`
- **THEN** gateway menampilkan nama-nama tag yang tersimpan tanpa pernah
  menampilkan nilai password apa pun

#### Scenario: Tag yang diminta tidak ada saat resolve

- **WHEN** command memuat `{{pw:tag}}` untuk tag yang belum pernah
  ditambahkan
- **THEN** eksekusi dibatalkan untuk request tersebut, response
  menyertakan pesan error yang menyebut tag tidak ditemukan, dan tidak ada
  command yang terkirim ke SSH

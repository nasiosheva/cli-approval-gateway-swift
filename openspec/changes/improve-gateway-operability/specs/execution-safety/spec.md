# Spec Delta

## Purpose

Mencegah satu request bermasalah (command yang menggantung atau host tujuan yang salah) memblokir seluruh antrean atau membuang approval operator untuk request yang pasti gagal.

## ADDED Requirements

### Requirement: Eksekusi SSH dibatasi waktu
Gateway SHALL membatasi durasi eksekusi SSH per request dengan `GATEWAY_SSH_TIMEOUT_SECONDS` (default 120 detik). Request yang melewati batas waktu SHALL dihentikan, SHALL ditandai status `timed-out`, dan SHALL NOT membuat watcher menggantung tanpa batas.

#### Scenario: Command SSH melewati batas waktu
- **WHEN** command yang dijalankan tidak selesai sebelum batas waktu tercapai
- **THEN** gateway menghentikan proses SSH, menulis response dengan status `timed-out` berisi output yang sempat diterima, dan melanjutkan ke request berikutnya di antrean

### Requirement: Host tujuan divalidasi sebelum approval
Gateway SHALL memvalidasi host tujuan (dari `#GATEWAY-HOST:` atau default) sebelum meminta approval Touch ID/Face ID. Alias yang cocok dengan konfigurasi SSH dan hostname/IP yang dapat di-resolve diterima; host yang tidak dikenal dan tidak dapat di-resolve SHALL ditolak dengan status `host-unknown` tanpa memicu dialog approval. Validasi SHALL NOT membuka koneksi SSH.

#### Scenario: Request menyertakan host yang salah ketik
- **WHEN** `#GATEWAY-HOST:` pada request menunjuk host yang tidak dikenal di konfigurasi SSH dan tidak dapat di-resolve
- **THEN** gateway menolak request dengan status `host-unknown`, tidak memanggil approval, dan request tetap mengikuti jalur finalize normal

#### Scenario: Request menyertakan host yang valid
- **WHEN** host tujuan dikenal di konfigurasi SSH
- **THEN** gateway melanjutkan ke approval dan eksekusi seperti biasa

#### Scenario: Host adalah hostname atau IP yang bisa di-resolve
- **WHEN** host tujuan bukan alias SSH tetapi hostname/IP dapat di-resolve
- **THEN** gateway melanjutkan ke approval dan eksekusi seperti biasa

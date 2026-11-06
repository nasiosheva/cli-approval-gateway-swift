# Spec Delta

## Purpose

Memberi operator sinyal yang jelas bahwa watcher masih hidup saat idle, dan bahwa ada request yang menunggu approval, tanpa harus memantau terminal terus-menerus.

## ADDED Requirements

### Requirement: Watcher melaporkan tanda hidup saat idle
Gateway SHALL mencetak baris heartbeat singkat setiap `GATEWAY_IDLE_HEARTBEAT_SECONDS` (default 300 detik) ketika tidak ada request baru di `requests/`, SHALL NOT mencetak heartbeat pada setiap iterasi polling, dan SHALL menonaktifkannya jika nilainya `0`.

#### Scenario: Watcher idle melewati ambang waktu
- **WHEN** tidak ada request baru di `requests/` selama lebih dari ambang waktu idle
- **THEN** gateway mencetak satu baris heartbeat lalu menunggu ambang waktu berikutnya sebelum mencetak lagi

### Requirement: Operator diberi notifikasi saat approval menunggu
Gateway SHALL mengirim notifikasi sistem best-effort saat request baru diklaim dan akan meminta approval. Kegagalan mengirim notifikasi SHALL NOT menggagalkan pemrosesan request.

#### Scenario: Request baru diklaim dan menunggu approval
- **WHEN** gateway mengklaim request dan akan memanggil approval Touch ID/Face ID
- **THEN** gateway mengirim notifikasi sistem kepada operator sebelum/menjelang dialog approval muncul

#### Scenario: Pengiriman notifikasi gagal
- **WHEN** mekanisme notifikasi sistem tidak tersedia atau gagal dipanggil
- **THEN** gateway tetap melanjutkan proses approval dan eksekusi request seperti biasa

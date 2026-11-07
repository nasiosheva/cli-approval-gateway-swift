# Catatan verifikasi manual

## 7 November 2026

- Watcher dijalankan dengan direktori data sementara, interval polling 0,2 detik, dan heartbeat 0,5 detik. Empat heartbeat teramati selama tiga detik idle setelah perbaikan loop.
- Pada percobaan awal, request dengan host yang tidak dapat di-resolve justru mencapai approval. Investigasi menunjukkan pemisahan baris CRLF pada output diagnostik SSH menyebabkan aturan wildcard `*` dianggap sebagai alias host spesifik.
- Setelah perbaikan CRLF, request dengan host yang sama menghasilkan `host-unknown` dan `approved: false`, berpindah ke `processed/`, serta tidak tertinggal di `processing/`. Tidak ada pesan kegagalan approval pada output watcher.
- Operator mengonfirmasi notifikasi muncul pada setiap approval. Timeout melalui watcher belum teramati secara manual karena approval perangkat tidak tersedia dalam sandbox; hasil self-test tiruan tidak menggantikan pemeriksaan tersebut.
- Seluruh data request dan response pengujian berada di direktori sementara. Tidak ada secret atau command remote yang digunakan.

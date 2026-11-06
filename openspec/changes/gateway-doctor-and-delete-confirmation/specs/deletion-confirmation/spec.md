# Spec Delta

## Purpose

Mengurangi penghapusan massal yang tidak disengaja dengan persetujuan eksplisit operator.

## ADDED Requirements

### Requirement: Konfirmasi penghapusan massal
Perintah `clear-responses` dan `clear-audit` SHALL meminta konfirmasi interaktif yang menyebut target sebelum menghapus, kecuali opsi `--yes` diberikan secara eksplisit.

#### Scenario: Operator menyetujui
- **WHEN** operator menjawab `y` atau `yes` tanpa membedakan huruf besar dan kecil
- **THEN** perintah melanjutkan penghapusan target yang disebutkan

#### Scenario: Operator membatalkan
- **WHEN** jawaban lain atau EOF diterima
- **THEN** tidak ada data target yang dihapus dan pembatalan dilaporkan

#### Scenario: Tidak ada terminal interaktif
- **WHEN** perintah dijalankan tanpa terminal interaktif dan tanpa `--yes`
- **THEN** perintah gagal dengan exit code bukan nol tanpa menghapus data

#### Scenario: Otomasi eksplisit
- **WHEN** opsi `--yes` diberikan dengan benar
- **THEN** penghapusan berlanjut tanpa prompt dan tetap menghormati lock watcher

#### Scenario: Argumen tidak valid
- **WHEN** argumen tambahan tidak dikenali
- **THEN** perintah gagal tanpa menghapus data

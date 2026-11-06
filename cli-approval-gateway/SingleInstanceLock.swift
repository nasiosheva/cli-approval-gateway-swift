// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Single-instance lock
//
// Mencegah dua watcher berjalan bersamaan di base dir yang sama secara
// diam-diam (misalnya karena dipicu tidak sengaja dari sesi terminal/agent
// lain). Berbeda dari PID file, advisory lock lewat `flock` otomatis
// terlepas saat proses keluar dengan cara apa pun — termasuk crash atau
// `kill -9` — jadi tidak ada risiko lock "basi" yang perlu dibersihkan
// manual setelah proses sebelumnya mati tidak normal.

enum SingleInstanceLockError: Error, CustomStringConvertible {
    case openFailed(Int32)
    case alreadyLocked

    var description: String {
        switch self {
        case .openFailed(let errnoValue):
            return "gagal membuka file lock (errno \(errnoValue)): \(String(cString: strerror(errnoValue)))"
        case .alreadyLocked:
            return "instance gateway lain sudah berjalan dan memegang lock ini"
        }
    }
}

/// Mengambil lock eksklusif non-blocking di `url`. Mengembalikan file
/// descriptor yang HARUS tetap dibuka sepanjang hidup proses (lock terikat
/// ke fd ini) — jangan ditutup sampai proses berhenti.
func acquireSingleInstanceLock(at url: URL) throws -> Int32 {
    let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else {
        throw SingleInstanceLockError.openFailed(errno)
    }

    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        throw SingleInstanceLockError.alreadyLocked
    }

    return fd
}

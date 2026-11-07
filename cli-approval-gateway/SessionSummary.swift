// Mories Deo Hutapea,S.E.,S.Kom
import Foundation

final class SessionSummary {
    private(set) var succeeded = 0
    private(set) var failed = 0
    private(set) var rejected = 0

    func record(_ payload: [String: Any]) {
        let status = payload["status"] as? String
        if status == nil && payload["approved"] as? Bool == false {
            rejected += 1
        } else if status == nil && payload["exitCode"] as? Int32 == 0 {
            succeeded += 1
        } else {
            failed += 1
        }
    }

    func printSummary() {
        print("Ringkasan sesi: berhasil=\(succeeded), gagal=\(failed), ditolak=\(rejected).")
    }
}

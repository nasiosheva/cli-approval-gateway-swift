// Mories Deo Hutapea,S.E.,S.Kom

import Foundation

func sendApprovalNotification(id: String, host: String, executableURL: URL = URL(fileURLWithPath: "/usr/bin/osascript")) -> Bool {
    func literal(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(singleLine)\""
    }

    let message = "Request \(id) di \(host) menunggu approval."
    let script = "display notification \(literal(message)) with title \(literal("CLI Approval Gateway"))"
    let result = runProcessCapturingOutput(
        executableURL: executableURL,
        arguments: ["-e", script],
        stdinData: nil,
        timeoutSeconds: 2
    )
    return result.exitCode == 0 && !result.timedOut
}

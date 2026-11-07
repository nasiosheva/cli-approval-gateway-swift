// Mories Deo Hutapea,S.E.,S.Kom
import Foundation
import Darwin

private let hostCheckTimeout: TimeInterval = 10

// A separate process group allows the deadline to stop SSH and its proxy children.
func runHostCheckProcess(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
    var output: [Int32] = [0, 0]
    guard pipe(&output) == 0 else { return CommandResult(exitCode: -1, stdout: "", stderr: "Gagal membuat pipe.") }
    defer { close(output[0]); close(output[1]) }
    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attributes)
    defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, output[1], STDERR_FILENO)
    posix_spawn_file_actions_addclose(&actions, output[0])
    posix_spawn_file_actions_addclose(&actions, output[1])
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)
    let strings = ([executable] + arguments).map { strdup($0) }
    defer { for string in strings { free(string) } }
    var argv = strings + [nil]
    var pid: pid_t = 0
    let status = posix_spawn(&pid, executable, &actions, &attributes, &argv, environ)
    guard status == 0 else { return CommandResult(exitCode: -1, stdout: "", stderr: "Gagal menjalankan SSH: \(String(cString: strerror(status)))") }
    close(output[1]); output[1] = -1
    _ = fcntl(output[0], F_SETFL, O_NONBLOCK)
    let deadline = Date().addingTimeInterval(timeout)
    var data = Data()
    var processStatus: Int32 = 0
    var exited = false
    var eof = false
    while Date() < deadline && !(exited && eof) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(output[0], &buffer, buffer.count)
        if count > 0 { data.append(contentsOf: buffer.prefix(count)) }
        else if count == 0 { eof = true }
        if !exited { exited = waitpid(pid, &processStatus, WNOHANG) == pid }
        if !(exited && eof) { usleep(10_000) }
    }
    let timedOut = !(exited && eof)
    if timedOut {
        kill(-pid, SIGKILL)
        if !exited { _ = waitpid(pid, &processStatus, 0) }
    }
    let code: Int32 = timedOut ? -1 : ((processStatus & 0x7f) == 0 ? (processStatus >> 8) & 0xff : 128 + (processStatus & 0x7f))
    return CommandResult(exitCode: code, stdout: "", stderr: String(decoding: data, as: UTF8.self), timedOut: timedOut)
}

func validHostCheckTarget(_ host: String) -> Bool {
    !host.isEmpty && !host.hasPrefix("-") && !host.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
}

func hostCheckArguments(_ host: String) -> [String] {
    ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "UpdateHostKeys=no", "-o", "ConnectTimeout=5", "-o", "NumberOfPasswordPrompts=0", host, "true"]
}

func runHostCheck(_ args: [String]) -> Never {
    guard args.count == 2, args[0] == "check", validHostCheckTarget(args[1]) else {
        FileHandle.standardError.write(Data("Penggunaan: host check <host> (host tidak boleh berupa opsi SSH).\n".utf8))
        exit(2)
    }
    let result = runHostCheckProcess(executable: "/usr/bin/ssh", arguments: hostCheckArguments(args[1]), timeout: hostCheckTimeout)
    if !result.stderr.isEmpty { print(result.stderr, terminator: result.stderr.hasSuffix("\n") ? "" : "\n") }
    if result.timedOut { print("Pemeriksaan SSH melewati batas waktu.") }
    else { print(result.exitCode == 0 ? "Koneksi SSH berhasil." : "Pemeriksaan SSH gagal (exit code \(result.exitCode)).") }
    exit(result.exitCode == 0 && !result.timedOut ? 0 : 1)
}

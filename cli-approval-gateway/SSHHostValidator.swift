// Mories Deo Hutapea,S.E.,S.Kom

import Foundation
import Darwin

protocol SSHHostValidating {
    func isValid(_ host: String) -> Bool
}

struct SSHHostValidator: SSHHostValidating {
    private let sshConfigURL: URL?
    private let hostnameResolver: (String) -> Bool

    init(sshConfigURL: URL? = nil, hostnameResolver: @escaping (String) -> Bool = SSHHostValidator.canResolve) {
        self.sshConfigURL = sshConfigURL
        self.hostnameResolver = hostnameResolver
    }

    func isValid(_ host: String) -> Bool {
        let candidate = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate == host,
              !candidate.hasPrefix("-"),
              !candidate.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return false
        }

        var arguments = ["-G", "-vv"]
        if let sshConfigURL {
            arguments += ["-F", sshConfigURL.path]
        }
        arguments.append(candidate)
        let result = runProcessCapturingOutput(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: arguments,
            stdinData: nil,
            timeoutSeconds: 3
        )
        guard result.exitCode == 0, !result.timedOut else { return false }

        var options: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            options[String(parts[0])] = String(parts[1])
        }
        let resolvedHost = options["hostname"] ?? candidate
        let hasMatchingSSHAlias = result.stderr
            .split(separator: "\n")
            .contains { line in
                guard let range = line.range(of: "Applying options for ") else { return false }
                return line[range.upperBound...].trimmingCharacters(in: .whitespaces) != "*"
            }
        let usesProxy = (options["proxycommand"] ?? "none") != "none"
            || (options["proxyjump"] ?? "none") != "none"
        return hasMatchingSSHAlias || usesProxy || resolvedHost != candidate || hostnameResolver(resolvedHost)
    }

    private static func canResolve(_ hostname: String) -> Bool {
        var addressInfo = addrinfo()
        addressInfo.ai_family = AF_UNSPEC
        addressInfo.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &addressInfo, &result)
        if let result {
            freeaddrinfo(result)
        }
        return status == 0
    }
}

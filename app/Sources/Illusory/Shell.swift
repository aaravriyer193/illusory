import Foundation

/// Bounded shell execution.
///
/// The command comes from a language model, so it is treated as untrusted input:
/// screened against patterns that are destructive or impossible to undo, confined
/// to the user's home directory, and killed if it overruns. None of this makes an
/// arbitrary command safe — it makes the obvious catastrophes unreachable, which
/// is the most a denylist can honestly claim.
enum Shell {
    enum ShellError: LocalizedError {
        case refused(String)
        case timedOut
        case failed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .refused(let why): return "Refused: \(why)"
            case .timedOut: return "Command took too long and was stopped."
            case .failed(let code, let err): return "Exited \(code): \(err.prefix(140))"
            }
        }
    }

    /// Patterns that are either irreversible or hand over the machine entirely.
    private static let forbidden: [(pattern: String, why: String)] = [
        ("rm -rf /", "recursive delete of a root path"),
        ("rm -fr /", "recursive delete of a root path"),
        ("sudo", "privilege escalation"),
        ("mkfs", "formatting a filesystem"),
        ("dd if=", "raw disk write"),
        ("diskutil", "disk management"),
        ("shutdown", "power control"),
        ("reboot", "power control"),
        ("killall", "killing processes indiscriminately"),
        ("launchctl", "changing what runs at login"),
        ("| sh", "piping a download into a shell"),
        ("| bash", "piping a download into a shell"),
        ("curl", "network fetch"),
        ("wget", "network fetch"),
        ("ssh", "remote access"),
        ("scp", "remote copy"),
        ("git push", "publishing"),
        ("npm publish", "publishing"),
        (":(){", "fork bomb"),
        ("/System", "system directory"),
        ("~/.ssh", "private keys"),
        ("security ", "keychain access"),
    ]

    static func screen(_ command: String) throws {
        let lowered = command.lowercased()
        for entry in forbidden where lowered.contains(entry.pattern) {
            throw ShellError.refused(entry.why)
        }
    }

    @discardableResult
    static func run(_ command: String, cwd: String?, timeout: TimeInterval = 20) async throws -> String {
        try screen(command)

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directory = cwd ?? home
        guard directory.hasPrefix(home) else {
            throw ShellError.refused("working directory outside your home folder")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        let deadline = Task {
            try await Task.sleep(for: .seconds(timeout))
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        deadline.cancel()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ShellError.failed(process.terminationStatus, stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }
}

import Foundation

private struct Unsafe<T>: @unchecked Sendable { let value: T }

/// Launches, supervises, and terminates an MCP server subprocess.
///
/// The manager owns the `Process` and its stdio pipes. It returns a configured
/// `MCPTransport` connected to the child's stdin/stdout. Stderr is captured
/// line-by-line into `stderrLines` for surfacing install / runtime failures.
actor MCPProcessManager {
    let config: MCPServerConfig
    private var processBox: Unsafe<Process>?
    private var terminationContinuation: CheckedContinuation<Int32, Never>?
    private(set) var stderrLines: [String] = []
    private let maxStderrLines = 200
    private var stderrTask: Task<Void, Never>?
    private lazy var logURL: URL = RuntimeConstants.appSupport
        .appendingPathComponent("mcp-\(config.name).log")

    init(config: MCPServerConfig) {
        self.config = config
    }

    var isRunning: Bool {
        processBox?.value.isRunning == true
    }

    func currentStderr() -> [String] { stderrLines }

    /// Launch the subprocess and return a transport wired to its stdio.
    func launch() throws -> MCPTransport {
        guard processBox == nil else {
            throw MCPError.alreadyRunning
        }
        appendLog("Launching \(config.name) command=\(config.command) args=\(config.args.joined(separator: " "))")

        let executable: String
        do {
            executable = try resolveExecutablePath(config.command)
        } catch {
            appendLog("Launch failed: \(error.localizedDescription)")
            throw error
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = config.args

        // Start from the app's environment but strip variables that confuse
        // a bundled Python venv. Xcode's debug env sets PYTHONPATH/PYTHONHOME
        // and often VIRTUAL_ENV pointing at unrelated interpreters — these
        // cause our venv Python to import from the wrong place and hang or
        // crash silently during MCP startup.
        var env = ProcessInfo.processInfo.environment
        for key in [
            "PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV",
            "PYTHONSTARTUP", "PYTHONEXECUTABLE", "PYTHONNOUSERSITE",
        ] {
            env.removeValue(forKey: key)
        }
        for (k, v) in config.env { env[k] = v }
        env["PATH"] = enrichedPATH(from: env["PATH"])
        proc.environment = env

        if let cwd = config.cwd {
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        // Termination handler — hop into the actor to record exit.
        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            Task { [weak self] in
                await self?.handleTermination(status: status)
            }
        }

        do {
            try proc.run()
        } catch {
            appendLog("Launch failed: \(error.localizedDescription)")
            throw MCPError.launchFailed(error.localizedDescription)
        }

        appendLog("Process started pid=\(proc.processIdentifier)")
        processBox = Unsafe(value: proc)
        startStderrCapture(handle: stderrPipe.fileHandleForReading)

        return MCPTransport(
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading,
            writeFraming: config.writeFraming == .ndjson ? .ndjson : .contentLength
        )
    }

    /// Terminate the subprocess (SIGTERM), waiting up to `timeout` seconds.
    func terminate(timeout: TimeInterval = 3.0, reason: String = "unspecified") async {
        guard let box = processBox else { return }
        let proc = box.value
        guard proc.isRunning else {
            processBox = nil
            return
        }

        appendLog("Terminating pid=\(proc.processIdentifier) reason=\(reason)")
        proc.terminate()

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if proc.isRunning {
            // Hard kill if it didn't exit politely.
            appendLog("Terminate timeout exceeded, sending SIGKILL pid=\(proc.processIdentifier)")
            kill(proc.processIdentifier, SIGKILL)
        }
        processBox = nil
        stderrTask?.cancel()
        stderrTask = nil
    }

    /// Suspend until the process exits, returning its exit status.
    func waitForExit() async -> Int32 {
        guard let box = processBox, box.value.isRunning else {
            return processBox?.value.terminationStatus ?? 0
        }
        return await withCheckedContinuation { cont in
            self.terminationContinuation = cont
        }
    }

    // MARK: - Private

    private func handleTermination(status: Int32) {
        appendLog("Process exited status=\(status)")
        processBox = nil
        stderrTask?.cancel()
        stderrTask = nil
        terminationContinuation?.resume(returning: status)
        terminationContinuation = nil
    }

    private func startStderrCapture(handle: FileHandle) {
        let box = Unsafe(value: handle)
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            var buffer = Data()
            let h = box.value
            while !Task.isCancelled {
                let chunk: Data?
                do { chunk = try h.read(upToCount: 4096) } catch { break }
                guard let chunk, !chunk.isEmpty else { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<nl)
                    if let s = String(data: line, encoding: .utf8) {
                        await self?.appendStderr(s)
                    }
                    let next = buffer.index(after: nl)
                    buffer.removeSubrange(buffer.startIndex..<next)
                }
            }
            if !buffer.isEmpty, let trailing = String(data: buffer, encoding: .utf8) {
                await self?.appendStderr(trailing)
            }
        }
    }

    private func appendStderr(_ line: String) {
        stderrLines.append(line)
        if stderrLines.count > maxStderrLines {
            stderrLines.removeFirst(stderrLines.count - maxStderrLines)
        }
        appendLog("[stderr] \(line)")
    }

    private func appendLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let msg = "\(ts) \(line)\n"
        let data = Data(msg.utf8)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: RuntimeConstants.appSupport, withIntermediateDirectories: true)
            if fm.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Logging must never break MCP process management.
        }
    }

    private func resolveExecutablePath(_ command: String) throws -> String {
        let fm = FileManager.default
        if command.contains("/") {
            guard fm.isExecutableFile(atPath: command) else {
                throw MCPError.launchFailed("Command '\(command)' is not executable")
            }
            return command
        }

        for dir in executableSearchPaths() {
            let candidate = String(dir) + "/" + command
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw MCPError.launchFailed("Command '\(command)' not found on PATH")
    }

    private func executableSearchPaths() -> [Substring] {
        let base = enrichedPATH(from: ProcessInfo.processInfo.environment["PATH"])
        return base.split(separator: ":")
    }

    private func enrichedPATH(from rawPATH: String?) -> String {
        var ordered: [String] = []
        var seen: Set<String> = []

        func add(_ path: String) {
            guard !path.isEmpty, !seen.contains(path) else { return }
            seen.insert(path)
            ordered.append(path)
        }

        (rawPATH ?? "").split(separator: ":").forEach { add(String($0)) }
        add("/opt/homebrew/bin")
        add("/usr/local/bin")
        add("/usr/bin")
        add("/bin")
        add("/usr/sbin")
        add("/sbin")
        return ordered.joined(separator: ":")
    }
}

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

    init(config: MCPServerConfig) {
        self.config = config
    }

    var isRunning: Bool {
        processBox?.value.isRunning == true
    }

    /// Launch the subprocess and return a transport wired to its stdio.
    func launch() throws -> MCPTransport {
        guard processBox == nil else {
            throw MCPError.alreadyRunning
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: config.command)
        proc.arguments = config.args

        var env = ProcessInfo.processInfo.environment
        for (k, v) in config.env { env[k] = v }
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
            throw MCPError.launchFailed(error.localizedDescription)
        }

        processBox = Unsafe(value: proc)
        startStderrCapture(handle: stderrPipe.fileHandleForReading)

        return MCPTransport(
            stdin: stdinPipe.fileHandleForWriting,
            stdout: stdoutPipe.fileHandleForReading
        )
    }

    /// Terminate the subprocess (SIGTERM), waiting up to `timeout` seconds.
    func terminate(timeout: TimeInterval = 3.0) async {
        guard let box = processBox else { return }
        let proc = box.value
        guard proc.isRunning else {
            processBox = nil
            return
        }

        proc.terminate()

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if proc.isRunning {
            // Hard kill if it didn't exit politely.
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
        }
    }

    private func appendStderr(_ line: String) {
        stderrLines.append(line)
        if stderrLines.count > maxStderrLines {
            stderrLines.removeFirst(stderrLines.count - maxStderrLines)
        }
    }
}

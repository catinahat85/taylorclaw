import Foundation

actor MemPalaceServer {
    static let shared = MemPalaceServer()

    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }
        guard FileManager.default.fileExists(
            atPath: RuntimeConstants.venvPython.path) else {
            throw RuntimeError.notInstalled
        }

        let proc = Process()
        proc.executableURL = RuntimeConstants.venvPython
        proc.arguments = [
            "-m", "mempalace.mcp_server",
            "--data-dir", RuntimeConstants.mempalaceDir.path
        ]
        var env = ProcessInfo.processInfo.environment
        env["MEM_PALACE_DATA_DIR"] = RuntimeConstants.mempalaceDir.path
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] _ in
            Task { await self?.clearProcess() }
        }

        try proc.run()
        process = proc
    }

    func stop() {
        process?.terminate()
        process?.waitUntilExit()
        process = nil
    }

    // MARK: - Private

    private func clearProcess() {
        process = nil
    }
}

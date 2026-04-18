import Foundation

/// Bridges non-`Sendable` Foundation IPC types across isolation boundaries.
/// Safe because each wrapped handle is only touched inside one actor / task.
private struct Unsafe<T>: @unchecked Sendable { let value: T }

/// Newline-delimited JSON transport over a pair of stdio pipes.
///
/// MCP speaks JSON-RPC 2.0 framed as one JSON object per line on stdout/stdin.
/// The transport does not parse bodies — it just emits `Data` per line and
/// writes `Data + \n` on send.
actor MCPTransport {
    private let stdinBox: Unsafe<FileHandle>
    private let stdoutBox: Unsafe<FileHandle>
    private var readTask: Task<Void, Never>?
    private var yielder: AsyncStream<Data>.Continuation?
    private var isClosed = false

    /// Lines read from the child's stdout, one `Data` per line.
    let incoming: AsyncStream<Data>

    init(stdin: FileHandle, stdout: FileHandle) {
        self.stdinBox = Unsafe(value: stdin)
        self.stdoutBox = Unsafe(value: stdout)
        var c: AsyncStream<Data>.Continuation!
        self.incoming = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        self.yielder = c
    }

    /// Start the background reader. Must be called before awaiting `incoming`.
    func start() {
        guard readTask == nil, !isClosed else { return }
        let stdoutBox = self.stdoutBox
        let yielder = self.yielder
        readTask = Task.detached(priority: .utility) {
            var buffer = Data()
            let handle = stdoutBox.value
            while !Task.isCancelled {
                let chunk: Data?
                do {
                    chunk = try handle.read(upToCount: 4096)
                } catch {
                    break
                }
                guard let chunk, !chunk.isEmpty else { break } // EOF
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<nl)
                    if !line.isEmpty {
                        yielder?.yield(line)
                    }
                    let next = buffer.index(after: nl)
                    buffer.removeSubrange(buffer.startIndex..<next)
                }
            }
            yielder?.finish()
        }
    }

    /// Write a single JSON message (without trailing newline) to the child's stdin.
    func send(_ data: Data) throws {
        guard !isClosed else { throw MCPError.transportClosed }
        var payload = data
        payload.append(0x0A)
        try stdinBox.value.write(contentsOf: payload)
    }

    /// Stop reading and close both pipe ends.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        readTask?.cancel()
        readTask = nil
        yielder?.finish()
        yielder = nil
        try? stdinBox.value.close()
        try? stdoutBox.value.close()
    }
}

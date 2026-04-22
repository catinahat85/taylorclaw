import Foundation

/// Bridges non-`Sendable` Foundation IPC types across isolation boundaries.
/// Safe because each wrapped handle is only touched inside one actor / task.
private struct Unsafe<T>: @unchecked Sendable { let value: T }

/// MCP stdio transport over a pair of pipes.
///
/// Modern MCP servers use HTTP-like stdio framing:
///   `Content-Length: <N>\r\n\r\n<JSON bytes>`
/// Some legacy servers emit newline-delimited JSON.
///
/// This transport accepts either framing on read, and writes the standard
/// `Content-Length` framed payloads.
actor MCPTransport {
    private let stdinBox: Unsafe<FileHandle>
    private let stdoutBox: Unsafe<FileHandle>
    private var readTask: Task<Void, Never>?
    private var yielder: AsyncStream<Data>.Continuation?
    private var isClosed = false

    /// Complete JSON messages read from the child's stdout.
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

                var advanced = true
                while advanced {
                    advanced = false
                    if let parsed = Self.consumeContentLengthMessage(from: &buffer) {
                        yielder?.yield(parsed)
                        advanced = true
                        continue
                    }
                    if let line = Self.consumeNewlineDelimitedMessage(from: &buffer) {
                        yielder?.yield(line)
                        advanced = true
                    }
                }
            }
            yielder?.finish()
        }
    }

    /// Write a single JSON message using MCP's `Content-Length` framing.
    func send(_ data: Data) throws {
        guard !isClosed else { throw MCPError.transportClosed }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(data)
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

private extension MCPTransport {
    static func consumeContentLengthMessage(from buffer: inout Data) -> Data? {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        guard let headerEndRange = buffer.range(of: separator) else {
            return nil
        }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerEndRange.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        var contentLength: Int?
        for rawLine in header.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if key.caseInsensitiveCompare("Content-Length") == .orderedSame {
                contentLength = Int(value)
                break
            }
        }
        guard let bodyLength = contentLength, bodyLength >= 0 else {
            return nil
        }

        let bodyStart = headerEndRange.upperBound
        guard buffer.count - bodyStart >= bodyLength else {
            return nil
        }
        let bodyEnd = bodyStart + bodyLength
        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return body
    }

    static func consumeNewlineDelimitedMessage(from buffer: inout Data) -> Data? {
        if let first = buffer.firstNonWhitespaceASCII {
            // When a framed message begins (`Content-Length: ...`), wait for
            // full headers/body instead of consuming header lines as NDJSON.
            if first == UInt8(ascii: "C") || first == UInt8(ascii: "c") {
                return nil
            }
        }
        guard let nl = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer.subdata(in: buffer.startIndex..<nl)
        let next = buffer.index(after: nl)
        buffer.removeSubrange(buffer.startIndex..<next)
        return line.isEmpty ? nil : line
    }
}

private extension Data {
    var firstNonWhitespaceASCII: UInt8? {
        for byte in self where byte != 0x20 && byte != 0x09 && byte != 0x0D && byte != 0x0A {
            return byte
        }
        return nil
    }
}

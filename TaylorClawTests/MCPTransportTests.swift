import XCTest
@testable import TaylorClaw

final class MCPTransportTests: XCTestCase {

    func testSendAppendsNewline() async throws {
        let up = Pipe()
        let down = Pipe()
        let transport = MCPTransport(
            stdin: up.fileHandleForWriting,
            stdout: down.fileHandleForReading
        )
        try await transport.send(Data("hello".utf8))
        try await transport.send(Data("world".utf8))

        let chunk = try up.fileHandleForReading.read(upToCount: 64)
        XCTAssertEqual(chunk, Data("hello\nworld\n".utf8))

        await transport.close()
    }

    func testReceivesLineDelimitedFrames() async throws {
        let up = Pipe()
        let down = Pipe()
        let transport = MCPTransport(
            stdin: up.fileHandleForWriting,
            stdout: down.fileHandleForReading
        )
        await transport.start()

        try down.fileHandleForWriting.write(contentsOf: Data("line1\nline2\n".utf8))

        var received: [String] = []
        let stream = await transport.incoming
        for await data in stream {
            received.append(String(decoding: data, as: UTF8.self))
            if received.count == 2 { break }
        }
        XCTAssertEqual(received, ["line1", "line2"])

        await transport.close()
    }

    func testReassemblesSplitFrames() async throws {
        let up = Pipe()
        let down = Pipe()
        let transport = MCPTransport(
            stdin: up.fileHandleForWriting,
            stdout: down.fileHandleForReading
        )
        await transport.start()

        try down.fileHandleForWriting.write(contentsOf: Data("par".utf8))
        try await Task.sleep(for: .milliseconds(20))
        try down.fileHandleForWriting.write(contentsOf: Data("tial\n".utf8))

        let stream = await transport.incoming
        var first: String?
        for await data in stream {
            first = String(decoding: data, as: UTF8.self)
            break
        }
        XCTAssertEqual(first, "partial")

        await transport.close()
    }
}

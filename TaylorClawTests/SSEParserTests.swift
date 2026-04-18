import XCTest
@testable import TaylorClaw

final class SSEParserTests: XCTestCase {
    func testParsesSingleEvent() {
        var parser = SSEParser()
        let events = parser.feed("data: hello\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "hello")
    }

    func testBuffersIncompleteEvents() {
        var parser = SSEParser()
        var events = parser.feed("data: partial")
        XCTAssertTrue(events.isEmpty)
        events = parser.feed("\n\n")
        XCTAssertEqual(events.first?.data, "partial")
    }

    func testParsesMultilineData() {
        var parser = SSEParser()
        let events = parser.feed("data: line1\ndata: line2\n\n")
        XCTAssertEqual(events.first?.data, "line1\nline2")
    }

    func testParsesEventField() {
        var parser = SSEParser()
        let events = parser.feed("event: message_start\ndata: {}\n\n")
        XCTAssertEqual(events.first?.event, "message_start")
        XCTAssertEqual(events.first?.data, "{}")
    }

    func testIgnoresComments() {
        var parser = SSEParser()
        let events = parser.feed(": keepalive\ndata: payload\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "payload")
    }

    func testHandlesCRLF() {
        var parser = SSEParser()
        let events = parser.feed("data: hi\r\n\r\n")
        XCTAssertEqual(events.first?.data, "hi")
    }

    func testMultipleEventsInOneFeed() {
        var parser = SSEParser()
        let events = parser.feed("data: a\n\ndata: b\n\n")
        XCTAssertEqual(events.map(\.data), ["a", "b"])
    }
}

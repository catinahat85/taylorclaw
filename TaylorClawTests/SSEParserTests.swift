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

    // MARK: - OpenRouter fixture tests

    /// Recorded OpenRouter/OpenAI-compatible stream: each data: line is a complete
    /// event with a blank-line separator. Verifies the text extraction path.
    func testOpenRouterFixtureWithBlankLineSeparators() {
        let fixture = """
        data: {"id":"gen-001","choices":[{"delta":{"role":"assistant","content":""},"index":0,"finish_reason":null}],"model":"openai/gpt-4.1-mini","object":"chat.completion.chunk"}\n\n\
        data: {"id":"gen-001","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}],"model":"openai/gpt-4.1-mini","object":"chat.completion.chunk"}\n\n\
        data: {"id":"gen-001","choices":[{"delta":{"content":" world"},"index":0,"finish_reason":null}],"model":"openai/gpt-4.1-mini","object":"chat.completion.chunk"}\n\n\
        data: {"id":"gen-001","choices":[{"delta":{},"index":0,"finish_reason":"stop"}],"model":"openai/gpt-4.1-mini","object":"chat.completion.chunk"}\n\n\
        data: [DONE]\n\n
        """

        var parser = SSEParser()
        let events = parser.feed(fixture)

        let nonDone = events.filter { $0.data != "[DONE]" }
        let texts = nonDone.compactMap { event -> String? in
            guard let data = event.data.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OpenRouterChunk.self, from: data)
            else { return nil }
            return chunk.choices.first?.delta.content
        }.filter { !$0.isEmpty }

        XCTAssertEqual(texts, ["Hello", " world"])

        let hasDone = events.contains { $0.data == "[DONE]" }
        XCTAssertTrue(hasDone)
    }

    /// OpenRouter sometimes sends keep-alive comments (": OPENROUTER PROCESSING")
    /// before the first token. These must be ignored, not crash or stall the parser.
    func testOpenRouterKeepAliveComments() {
        let fixture = ": OPENROUTER PROCESSING\n\n" +
                      "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n" +
                      "data: [DONE]\n\n"
        var parser = SSEParser()
        let events = parser.feed(fixture)
        let dataEvents = events.filter { !$0.data.isEmpty && $0.data != "[DONE]" }
        XCTAssertFalse(dataEvents.isEmpty, "Should have parsed the data event after keep-alive comment")
    }

    /// Verifies that a model ID containing a colon (e.g. minimax/minimax-m2.5:free)
    /// survives the Preferences qualifiedID round-trip intact.
    func testModelIDWithColonRoundtrip() {
        let original = "minimax/minimax-m2.5:free"
        let model = LLMModel(provider: .openrouter, id: original, displayName: original)
        let qualified = model.qualifiedID          // "openrouter:minimax/minimax-m2.5:free"

        // Simulate Preferences.parseQualifiedID
        let parts = qualified.split(separator: ":", maxSplits: 1).map(String.init)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], "openrouter")
        XCTAssertEqual(parts[1], original, "Model ID with colon must survive round-trip")
    }
}

// Minimal decodable matching OpenRouterProvider's private Chunk type
private struct OpenRouterChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: Delta
    }
    struct Delta: Decodable {
        let content: String?
    }
}

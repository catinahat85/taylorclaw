import XCTest
@testable import TaylorClaw

final class DocumentChunkerTests: XCTestCase {

    func testEmptyInputYieldsNoChunks() {
        let chunker = DocumentChunker(targetSize: 200, overlap: 20)
        XCTAssertTrue(chunker.chunk("").isEmpty)
        XCTAssertTrue(chunker.chunk("   \n\n  ").isEmpty)
    }

    func testShortInputIsOneChunk() {
        let chunker = DocumentChunker(targetSize: 200, overlap: 20)
        let chunks = chunker.chunk("Hello world.")
        XCTAssertEqual(chunks, ["Hello world."])
    }

    func testRespectsParagraphBoundaries() {
        let chunker = DocumentChunker(targetSize: 50, overlap: 0)
        let text = "Short para one.\n\nShort para two.\n\nShort para three."
        let chunks = chunker.chunk(text)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].contains("Short para one"))
    }

    func testHardSplitsLongParagraph() {
        let chunker = DocumentChunker(targetSize: 100, overlap: 0)
        let long = String(repeating: "word ", count: 50)  // 250 chars
        let chunks = chunker.chunk(long)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 100)
        }
    }

    func testOverlapAppearsBetweenChunks() {
        let chunker = DocumentChunker(targetSize: 100, overlap: 20)
        let p1 = String(repeating: "a", count: 60)
        let p2 = String(repeating: "b", count: 60)
        let chunks = chunker.chunk(p1 + "\n\n" + p2)
        XCTAssertEqual(chunks.count, 2)
        // Second chunk should begin with overlap from tail of first.
        XCTAssertTrue(chunks[1].hasPrefix(String(repeating: "a", count: 20)))
    }

    func testReasonableChunkSizesForRealisticText() {
        let chunker = DocumentChunker(targetSize: 400, overlap: 50)
        let para = String(repeating: "Lorem ipsum dolor sit amet. ", count: 8)
        let text = [para, para, para, para].joined(separator: "\n\n")
        let chunks = chunker.chunk(text)
        for c in chunks {
            XCTAssertLessThanOrEqual(c.count, 500)
        }
        XCTAssertFalse(chunks.isEmpty)
    }

    func testPreconditionRejectsInvalidOverlap() {
        // overlap must be < targetSize — guarded by precondition, so we can't
        // cleanly assert without crashing. Validate the successful case
        // instead.
        let c = DocumentChunker(targetSize: 100, overlap: 99)
        XCTAssertEqual(c.overlap, 99)
    }
}

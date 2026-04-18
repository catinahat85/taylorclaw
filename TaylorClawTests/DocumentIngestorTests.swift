import XCTest
@testable import TaylorClaw

final class DocumentIngestorTests: XCTestCase {

    private var storeURL: URL!
    private var fileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taylorclaw-ingest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("documents.json")
        fileURL = dir.appendingPathComponent("sample.txt")
        let content = String(repeating: "Paragraph line.\n\n", count: 20)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        try await super.tearDown()
    }

    func testIngestTextFileChunksAndPersists() async throws {
        let store = DocumentStore(fileURL: storeURL)
        let uploader = CapturingUploader()
        let ingestor = DocumentIngestor(
            chunker: DocumentChunker(targetSize: 100, overlap: 20),
            store: store,
            uploader: uploader
        )
        let doc = try await ingestor.ingest(url: fileURL)
        XCTAssertEqual(doc.status, .ingested)
        XCTAssertGreaterThan(doc.chunkCount, 0)
        XCTAssertNotNil(doc.contentHash)
        XCTAssertNotNil(doc.externalID)

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)

        let received = await uploader.received
        XCTAssertEqual(received.count, 1)
        XCTAssertGreaterThan(received[0].chunks.count, 0)
    }

    func testDuplicateContentHashSkipsUpload() async throws {
        let store = DocumentStore(fileURL: storeURL)
        let uploader = CapturingUploader()
        let ingestor = DocumentIngestor(
            chunker: DocumentChunker(targetSize: 200, overlap: 20),
            store: store,
            uploader: uploader
        )
        _ = try await ingestor.ingest(url: fileURL)

        // Ingest the same file again from a new URL pointing at identical
        // content — the hash match should skip the uploader entirely.
        let twinURL = fileURL.deletingLastPathComponent().appendingPathComponent("twin.txt")
        try FileManager.default.copyItem(at: fileURL, to: twinURL)
        _ = try await ingestor.ingest(url: twinURL)

        let calls = await uploader.received
        XCTAssertEqual(calls.count, 1, "Uploader should only be called once for identical content")
        let all = try await store.all()
        XCTAssertEqual(all.count, 2, "Both documents should appear in the store")
    }

    func testUnsupportedKindFailsGracefully() async throws {
        let weirdURL = fileURL.deletingLastPathComponent().appendingPathComponent("unknown.xyz")
        try "data".write(to: weirdURL, atomically: true, encoding: .utf8)
        let store = DocumentStore(fileURL: storeURL)
        let ingestor = DocumentIngestor(
            chunker: DocumentChunker(),
            store: store,
            uploader: CapturingUploader()
        )
        do {
            _ = try await ingestor.ingest(url: weirdURL)
            XCTFail("Expected unsupportedKind to throw")
        } catch DocumentReaderError.unsupportedKind {
            // expected
        }
        let all = try await store.all()
        XCTAssertEqual(all.first?.status, .failed)
    }

    func testIngestWithoutUploaderStillChunksAndPersists() async throws {
        let store = DocumentStore(fileURL: storeURL)
        let ingestor = DocumentIngestor(
            chunker: DocumentChunker(targetSize: 200, overlap: 0),
            store: store,
            uploader: nil
        )
        let doc = try await ingestor.ingest(url: fileURL)
        XCTAssertEqual(doc.status, .ingested)
        XCTAssertNil(doc.externalID)
        XCTAssertGreaterThan(doc.chunkCount, 0)
    }

    func testSHA256IsDeterministic() {
        let h1 = DocumentIngestor.sha256("hello")
        let h2 = DocumentIngestor.sha256("hello")
        XCTAssertEqual(h1, h2)
        XCTAssertNotEqual(h1, DocumentIngestor.sha256("hellox"))
        XCTAssertEqual(h1.count, 64)
    }
}

// MARK: - Test doubles

actor CapturingUploader: DocumentUploader {
    struct Call: Sendable {
        let chunks: [String]
        let title: String
        let metadata: [String: String]
    }
    private(set) var received: [Call] = []

    func upload(
        chunks: [String],
        title: String,
        metadata: [String: String]
    ) async throws -> String {
        received.append(Call(chunks: chunks, title: title, metadata: metadata))
        return UUID().uuidString
    }
}

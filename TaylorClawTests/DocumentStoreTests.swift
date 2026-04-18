import XCTest
@testable import TaylorClaw

final class DocumentStoreTests: XCTestCase {

    private var tmpURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("taylorclaw-doctest-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL)
        try await super.tearDown()
    }

    func testUpsertAndRead() async throws {
        let store = DocumentStore(fileURL: tmpURL)
        let doc = Document(filename: "a.txt", kind: .text, chunkCount: 3, status: .ingested, contentHash: "h1")
        try await store.upsert(doc)
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.filename, "a.txt")
    }

    func testUpsertReplacesExisting() async throws {
        let store = DocumentStore(fileURL: tmpURL)
        var doc = Document(filename: "a.txt", kind: .text, chunkCount: 1, status: .pending)
        try await store.upsert(doc)
        doc.chunkCount = 5
        doc.status = .ingested
        try await store.upsert(doc)
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.chunkCount, 5)
        XCTAssertEqual(all.first?.status, .ingested)
    }

    func testFindByHash() async throws {
        let store = DocumentStore(fileURL: tmpURL)
        try await store.upsert(Document(filename: "a.txt", kind: .text, contentHash: "abc"))
        try await store.upsert(Document(filename: "b.txt", kind: .text, contentHash: "def"))
        let hit = try await store.findByHash("def")
        XCTAssertEqual(hit?.filename, "b.txt")
        let miss = try await store.findByHash("nope")
        XCTAssertNil(miss)
    }

    func testDelete() async throws {
        let store = DocumentStore(fileURL: tmpURL)
        let doc = Document(filename: "a.txt", kind: .text)
        try await store.upsert(doc)
        try await store.delete(id: doc.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testPersistenceAcrossInstances() async throws {
        let storeA = DocumentStore(fileURL: tmpURL)
        try await storeA.upsert(Document(filename: "a.txt", kind: .text))
        try await storeA.upsert(Document(filename: "b.pdf", kind: .pdf))

        let storeB = DocumentStore(fileURL: tmpURL)
        let all = try await storeB.all()
        XCTAssertEqual(all.count, 2)
    }

    func testDocumentKindFromURL() {
        XCTAssertEqual(DocumentKind.from(url: URL(filePath: "/x/a.txt")), .text)
        XCTAssertEqual(DocumentKind.from(url: URL(filePath: "/x/a.md")), .markdown)
        XCTAssertEqual(DocumentKind.from(url: URL(filePath: "/x/a.PDF")), .pdf)
        XCTAssertEqual(DocumentKind.from(url: URL(filePath: "/x/a.swift")), .code)
        XCTAssertEqual(DocumentKind.from(url: URL(filePath: "/x/a.docx")), .unknown)
        XCTAssertFalse(DocumentKind.unknown.isReadable)
        XCTAssertTrue(DocumentKind.text.isReadable)
    }
}

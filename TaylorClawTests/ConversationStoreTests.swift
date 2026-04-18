import XCTest
@testable import TaylorClaw

final class ConversationStoreTests: XCTestCase {
    private var tempURL: URL!
    private var store: ConversationStore!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        store = ConversationStore(fileURL: tempURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testEmptyOnFirstLoad() async throws {
        let all = try await store.all()
        XCTAssertEqual(all, [])
    }

    func testUpsertAddsConversation() async throws {
        let convo = Conversation(title: "First")
        try await store.upsert(convo)
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "First")
    }

    func testUpsertUpdatesExisting() async throws {
        var convo = Conversation(title: "Before")
        try await store.upsert(convo)
        convo.title = "After"
        try await store.upsert(convo)
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "After")
    }

    func testDeleteRemoves() async throws {
        let convo = Conversation(title: "to delete")
        try await store.upsert(convo)
        try await store.delete(id: convo.id)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testPersistsAcrossInstances() async throws {
        let convo = Conversation(
            title: "Persisted",
            messages: [Message(role: .user, content: "hi")]
        )
        try await store.upsert(convo)

        let second = ConversationStore(fileURL: tempURL)
        let all = try await second.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.messages.first?.content, "hi")
    }

    func testSortingByUpdatedAt() async throws {
        let older = Conversation(title: "older")
        let newer = Conversation(title: "newer")
        try await store.upsert(older)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await store.upsert(newer)
        let all = try await store.all()
        XCTAssertEqual(all.first?.title, "newer")
    }
}

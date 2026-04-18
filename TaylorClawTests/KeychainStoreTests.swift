import XCTest
@testable import Taylor_Claw

final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!
    private let testService = "com.catinahat85.taylorclaw.tests"

    override func setUp() async throws {
        store = KeychainStore(service: testService)
        for provider in ProviderID.allCases {
            try? await store.delete(for: provider)
        }
    }

    override func tearDown() async throws {
        for provider in ProviderID.allCases {
            try? await store.delete(for: provider)
        }
    }

    func testSaveLoadRoundtrip() async throws {
        try await store.save("sk-test-123", for: .anthropic)
        let loaded = try await store.load(for: .anthropic)
        XCTAssertEqual(loaded, "sk-test-123")
    }

    func testOverwriteExistingKey() async throws {
        try await store.save("first", for: .openai)
        try await store.save("second", for: .openai)
        let loaded = try await store.load(for: .openai)
        XCTAssertEqual(loaded, "second")
    }

    func testDeleteRemovesKey() async throws {
        try await store.save("to-delete", for: .gemini)
        try await store.delete(for: .gemini)
        let loaded = try await store.load(for: .gemini)
        XCTAssertNil(loaded)
    }

    func testLoadMissingReturnsNil() async throws {
        let loaded = try await store.load(for: .openrouter)
        XCTAssertNil(loaded)
    }

    func testDeleteMissingIsIdempotent() async throws {
        try await store.delete(for: .ollama)
        try await store.delete(for: .ollama)
    }

    func testHasKeyReportsPresence() async throws {
        var present = await store.hasKey(for: .anthropic)
        XCTAssertFalse(present)
        try await store.save("present", for: .anthropic)
        present = await store.hasKey(for: .anthropic)
        XCTAssertTrue(present)
    }
}

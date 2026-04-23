import XCTest
@testable import TaylorClaw

final class MCPServerStoreTests: XCTestCase {
    private var tempURL: URL!
    private var store: MCPServerStore!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        store = MCPServerStore(fileURL: tempURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testEmptyOnFirstLoad() async throws {
        let all = try await store.all()
        XCTAssertEqual(all, [])
    }

    func testUpsertAdds() async throws {
        let cfg = MCPServerConfig(name: "brave-search", command: "npx", args: ["-y", "pkg"])
        try await store.upsert(cfg)
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["brave-search"])
    }

    func testUpsertReplacesByName() async throws {
        try await store.upsert(MCPServerConfig(name: "brave-search", command: "npx"))
        try await store.upsert(MCPServerConfig(
            name: "brave-search",
            command: "npx",
            env: ["BRAVE_API_KEY": "abc"]
        ))
        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.env["BRAVE_API_KEY"], "abc")
    }

    func testDeleteRemoves() async throws {
        try await store.upsert(MCPServerConfig(name: "a", command: "cmd"))
        try await store.upsert(MCPServerConfig(name: "b", command: "cmd"))
        try await store.delete(name: "a")
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["b"])
    }

    func testPersistsAcrossInstances() async throws {
        try await store.upsert(MCPServerConfig(
            name: "fetch",
            command: "uvx",
            args: ["mcp-server-fetch"],
            env: [:],
            cwd: nil,
            autoStart: false,
            writeFraming: .ndjson
        ))
        let second = MCPServerStore(fileURL: tempURL)
        let all = try await second.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.command, "uvx")
        XCTAssertEqual(all.first?.autoStart, false)
        XCTAssertEqual(all.first?.writeFraming, .ndjson)
    }

    func testRenameUpdatesInPlace() async throws {
        try await store.upsert(MCPServerConfig(
            name: "old",
            command: "cmd",
            writeFraming: .ndjson
        ))
        let renamed = try await store.rename(oldName: "old", to: "new")
        XCTAssertTrue(renamed)
        let all = try await store.all()
        XCTAssertEqual(all.map(\.name), ["new"])
        XCTAssertEqual(all.first?.writeFraming, .ndjson)
    }

    func testDecodeDefaultsWriteFramingForLegacyJSON() async throws {
        let legacy = """
        [
          {
            "name": "legacy",
            "command": "npx",
            "args": ["-y", "pkg"],
            "env": {},
            "cwd": null,
            "autoStart": true
          }
        ]
        """
        try Data(legacy.utf8).write(to: tempURL, options: .atomic)
        let decoded = try await store.all()
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.writeFraming, .contentLength)
    }

    func testRenameRejectsCollision() async throws {
        try await store.upsert(MCPServerConfig(name: "a", command: "cmd"))
        try await store.upsert(MCPServerConfig(name: "b", command: "cmd"))
        let renamed = try await store.rename(oldName: "a", to: "b")
        XCTAssertFalse(renamed)
        let all = try await store.all()
        XCTAssertEqual(Set(all.map(\.name)), Set(["a", "b"]))
    }
}

final class MCPServerPresetTests: XCTestCase {
    func testCatalogHasBraveSearchAndFetch() {
        let ids = Set(MCPServerPreset.catalog.map(\.id))
        XCTAssertTrue(ids.contains("brave-search"))
        XCTAssertTrue(ids.contains("fetch"))
    }

    func testBraveSearchPresetCreatesValidConfig() {
        let preset = MCPServerPreset.braveSearch
        let cfg = preset.makeConfig(env: ["BRAVE_API_KEY": "test"])
        XCTAssertEqual(cfg.name, "brave-search")
        XCTAssertEqual(cfg.command, "npx")
        XCTAssertTrue(cfg.args.contains("@modelcontextprotocol/server-brave-search"))
        XCTAssertEqual(cfg.env["BRAVE_API_KEY"], "test")
    }

    func testPresetExposesRequiredEnvKeys() {
        let preset = MCPServerPreset.braveSearch
        XCTAssertTrue(preset.requiredEnv.contains { $0.key == "BRAVE_API_KEY" })
    }

    func testFetchPresetHasNoRequiredEnv() {
        XCTAssertTrue(MCPServerPreset.fetch.requiredEnv.isEmpty)
    }

    func testPresetCustomName() {
        let cfg = MCPServerPreset.braveSearch.makeConfig(name: "my-brave")
        XCTAssertEqual(cfg.name, "my-brave")
    }
}

import XCTest
@testable import TaylorClaw

final class ToolPolicyTests: XCTestCase {

    func testBlocklistTakesPrecedence() {
        let p = ToolPolicy(
            overrides: ["get_thing": .caution],
            blocklist: ["get_thing"]
        )
        XCTAssertEqual(p.risk(for: "get_thing"), .blocked)
    }

    func testOverrideBeatsHeuristic() {
        let p = ToolPolicy(overrides: ["delete_foo": .safe])
        XCTAssertEqual(p.risk(for: "delete_foo"), .safe)
    }

    func testHeuristicDestructive() {
        XCTAssertEqual(ToolPolicy().risk(for: "delete_file"), .destructive)
        XCTAssertEqual(ToolPolicy().risk(for: "drop_table"), .destructive)
        XCTAssertEqual(ToolPolicy().risk(for: "wipe_cache"), .destructive)
    }

    func testHeuristicCaution() {
        XCTAssertEqual(ToolPolicy().risk(for: "write_file"), .caution)
        XCTAssertEqual(ToolPolicy().risk(for: "send_email"), .caution)
        XCTAssertEqual(ToolPolicy().risk(for: "update_record"), .caution)
    }

    func testHeuristicSafe() {
        XCTAssertEqual(ToolPolicy().risk(for: "get_user"), .safe)
        XCTAssertEqual(ToolPolicy().risk(for: "list_files"), .safe)
        XCTAssertEqual(ToolPolicy().risk(for: "search_docs"), .safe)
    }

    func testUnknownFallsBackToDefault() {
        XCTAssertEqual(ToolPolicy(defaultRisk: .caution).risk(for: "zxcvb"), .caution)
        XCTAssertEqual(ToolPolicy(defaultRisk: .destructive).risk(for: "zxcvb"), .destructive)
    }

    func testDefaultPolicyKnowsMemPalaceTools() {
        let p = ToolPolicy.default
        XCTAssertEqual(p.risk(for: "mempalace_search"), .safe)
        XCTAssertEqual(p.risk(for: "mempalace_list_wings"), .safe)
        XCTAssertEqual(p.risk(for: "mempalace_add_drawer"), .caution)
        XCTAssertEqual(p.risk(for: "mempalace_delete_drawer"), .destructive)
        XCTAssertEqual(p.risk(for: "mempalace_clear_palace"), .destructive)
    }

    func testHeuristicDestructiveBeatsCaution() {
        // "delete" wins over "update" in a name with both.
        XCTAssertEqual(ToolPolicy().risk(for: "update_and_delete"), .destructive)
    }
}

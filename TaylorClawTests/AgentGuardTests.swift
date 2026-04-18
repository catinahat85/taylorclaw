import XCTest
@testable import TaylorClaw

final class AgentGuardTests: XCTestCase {

    // MARK: - Helpers

    private func makeGuard(
        policy: ToolPolicy = .default,
        prompter: any ApprovalPrompter = AutoApprovePrompter(),
        maxCallsPerTool: Int = 20
    ) -> (AgentGuard, AuditLog) {
        let log = AuditLog(fileURL: nil)
        let g = AgentGuard(
            policy: policy,
            prompter: prompter,
            auditLog: log,
            maxCallsPerTool: maxCallsPerTool
        )
        return (g, log)
    }

    // MARK: - Safe tools

    func testSafeToolAutoApproved() async throws {
        let (g, log) = makeGuard()
        try await g.authorize(
            toolName: "mempalace_search",
            serverName: "mempalace",
            arguments: .object(["q": .string("x")])
        )
        let entries = await log.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .autoApproved)
        XCTAssertEqual(entries.first?.risk, .safe)
    }

    // MARK: - Cautionary tools

    func testCautionToolPromptsOnce() async throws {
        let scripted = ScriptedPrompter(
            script: ["mempalace_add_drawer": [.allowOnce]],
            fallback: .deny
        )
        let (g, log) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "mempalace_add_drawer", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 1)
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .userApproved)
    }

    func testCautionToolSessionApprovalCachedForSubsequentCalls() async throws {
        let scripted = ScriptedPrompter(
            script: ["mempalace_add_drawer": [.allowForSession]],
            fallback: .deny
        )
        let (g, log) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "mempalace_add_drawer", serverName: "mempalace")
        try await g.authorize(toolName: "mempalace_add_drawer", serverName: "mempalace")
        try await g.authorize(toolName: "mempalace_add_drawer", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 1, "Should only prompt once per session")
        let entries = await log.all()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].outcome, .userApproved)
        XCTAssertEqual(entries[1].outcome, .sessionApproved)
        XCTAssertEqual(entries[2].outcome, .sessionApproved)
    }

    func testCautionDeniedThrows() async {
        let (g, log) = makeGuard(prompter: AutoDenyPrompter())
        do {
            try await g.authorize(toolName: "mempalace_add_drawer", serverName: "mempalace")
            XCTFail("Expected denial to throw")
        } catch SafetyError.denied(let t) {
            XCTAssertEqual(t, "mempalace_add_drawer")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .userDenied)
    }

    // MARK: - Destructive

    func testDestructivePromptsEveryCallEvenIfPreviouslyApproved() async throws {
        let scripted = ScriptedPrompter(
            script: ["mempalace_delete_drawer": [.allowForSession, .allowForSession, .allowForSession]],
            fallback: .deny
        )
        let (g, _) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "mempalace_delete_drawer", serverName: "mempalace")
        try await g.authorize(toolName: "mempalace_delete_drawer", serverName: "mempalace")
        try await g.authorize(toolName: "mempalace_delete_drawer", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 3, "Destructive must prompt every time")
        let approved = await g.isApprovedForSession("mempalace_delete_drawer")
        XCTAssertFalse(approved, "Destructive must never remember approval")
    }

    // MARK: - Blocked

    func testBlockedToolNeverPrompts() async {
        let scripted = ScriptedPrompter(fallback: .allowOnce)
        let policy = ToolPolicy(blocklist: ["rm_rf"])
        let (g, log) = makeGuard(policy: policy, prompter: scripted)
        do {
            try await g.authorize(toolName: "rm_rf", serverName: "shell")
            XCTFail("Blocked tool should throw")
        } catch SafetyError.blocked {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 0, "Blocked tools must not reach the prompter")
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .blocked)
    }

    // MARK: - Loop detection

    func testLoopLimitTrips() async throws {
        let (g, log) = makeGuard(
            prompter: AutoApprovePrompter(),
            maxCallsPerTool: 3
        )
        try await g.authorize(toolName: "mempalace_search", serverName: "mempalace")
        try await g.authorize(toolName: "mempalace_search", serverName: "mempalace")
        try await g.authorize(toolName: "mempalace_search", serverName: "mempalace")
        do {
            try await g.authorize(toolName: "mempalace_search", serverName: "mempalace")
            XCTFail("Expected loop limit")
        } catch SafetyError.loopLimitExceeded(_, let limit) {
            XCTAssertEqual(limit, 3)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
        let entries = await log.all()
        XCTAssertEqual(entries.last?.outcome, .loopLimit)
    }

    func testResetClearsState() async throws {
        let scripted = ScriptedPrompter(
            script: ["mempalace_add_drawer": [.allowForSession, .allowForSession]],
            fallback: .deny
        )
        let (g, _) = makeGuard(prompter: scripted)
        try await g.authorize(toolName: "mempalace_add_drawer", serverName: "mempalace")
        let approvedBefore = await g.isApprovedForSession("mempalace_add_drawer")
        XCTAssertTrue(approvedBefore)

        await g.reset()

        let approvedAfter = await g.isApprovedForSession("mempalace_add_drawer")
        XCTAssertFalse(approvedAfter)
        // After reset, we should prompt again.
        try await g.authorize(toolName: "mempalace_add_drawer", serverName: "mempalace")
        let seen = await scripted.seen
        XCTAssertEqual(seen.count, 2)
    }

    // MARK: - Result recording

    func testRecordResultAppendsToLog() async {
        let (g, log) = makeGuard()
        await g.recordResult(
            toolName: "mempalace_search",
            serverName: "mempalace",
            success: true
        )
        await g.recordResult(
            toolName: "mempalace_search",
            serverName: "mempalace",
            success: false,
            error: "timeout"
        )
        let entries = await log.all()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].outcome, .toolSuccess)
        XCTAssertEqual(entries[1].outcome, .toolError)
        XCTAssertEqual(entries[1].error, "timeout")
    }
}

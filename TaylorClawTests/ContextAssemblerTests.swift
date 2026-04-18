import XCTest
@testable import TaylorClaw

final class ContextAssemblerTests: XCTestCase {

    // MARK: - Chat mode

    func testChatModeEmitsEmptyPromptAndNoTools() async {
        let tools = [
            MCPTool(name: "echo", description: "echo", inputSchema: nil),
        ]
        let assembler = ContextAssembler(
            mode: .chat,
            budget: ContextBudget(totalTokens: 10_000),
            tools: tools
        )
        let history = [Message(role: .user, content: "hi")]
        let ctx = await assembler.assemble(messages: history, memoryQuery: "hi")
        XCTAssertEqual(ctx.systemPrompt, "")
        XCTAssertTrue(ctx.tools.isEmpty)
        XCTAssertTrue(ctx.memorySnippets.isEmpty)
        XCTAssertEqual(ctx.messages, history)
        XCTAssertFalse(ctx.truncated)
    }

    func testChatModeIgnoresMemoryRetriever() async {
        let retriever = StubMemoryRetriever(snippets: [
            MemorySnippet(text: "should not appear"),
        ])
        let assembler = ContextAssembler(
            mode: .chat,
            budget: ContextBudget(totalTokens: 10_000),
            memoryRetriever: retriever
        )
        let ctx = await assembler.assemble(
            messages: [Message(role: .user, content: "hi")],
            memoryQuery: "hi"
        )
        XCTAssertTrue(ctx.memorySnippets.isEmpty)
        XCTAssertFalse(ctx.systemPrompt.contains("should not appear"))
    }

    // MARK: - Agent mode

    func testAgentModeIncludesToolsSection() async {
        let tools = [
            MCPTool(name: "echo", description: "Echo text.", inputSchema: nil),
            MCPTool(name: "add", description: "Sum two numbers.", inputSchema: nil),
        ]
        let assembler = ContextAssembler(
            mode: .agent,
            budget: ContextBudget(totalTokens: 10_000),
            tools: tools
        )
        let ctx = await assembler.assemble(
            messages: [Message(role: .user, content: "hello")],
            memoryQuery: "hello"
        )
        XCTAssertTrue(ctx.systemPrompt.contains("Available tools"))
        XCTAssertTrue(ctx.systemPrompt.contains("`echo`"))
        XCTAssertTrue(ctx.systemPrompt.contains("`add`"))
        XCTAssertEqual(ctx.tools.map(\.name), ["echo", "add"])
    }

    func testAgentModeInjectsMemorySnippets() async {
        let retriever = StubMemoryRetriever(snippets: [
            MemorySnippet(text: "User prefers markdown", source: "profile"),
            MemorySnippet(text: "Project uses SwiftUI", source: "notes"),
        ])
        let assembler = ContextAssembler(
            mode: .agent,
            budget: ContextBudget(totalTokens: 10_000),
            memoryRetriever: retriever
        )
        let ctx = await assembler.assemble(
            messages: [Message(role: .user, content: "what framework?")],
            memoryQuery: "what framework?"
        )
        XCTAssertEqual(ctx.memorySnippets.count, 2)
        XCTAssertTrue(ctx.systemPrompt.contains("Relevant memory"))
        XCTAssertTrue(ctx.systemPrompt.contains("SwiftUI"))
        XCTAssertTrue(ctx.systemPrompt.contains("[profile]"))
    }

    func testAgentModeEmptyQuerySkipsMemory() async {
        let retriever = StubMemoryRetriever(snippets: [
            MemorySnippet(text: "should not appear"),
        ])
        let assembler = ContextAssembler(
            mode: .agent,
            budget: ContextBudget(totalTokens: 10_000),
            memoryRetriever: retriever
        )
        let ctx = await assembler.assemble(
            messages: [Message(role: .user, content: "hi")],
            memoryQuery: ""
        )
        XCTAssertTrue(ctx.memorySnippets.isEmpty)
    }

    // MARK: - History trimming

    func testTrimHistoryDropsOldestWhenOverBudget() {
        let msgs = (0..<10).map {
            Message(role: .user, content: String(repeating: "x", count: 40))
        }
        // Each message ~14 tokens. 10 msgs ~140 tokens. Budget = 50.
        let (kept, dropped) = ContextAssembler.trimHistory(msgs, tokenBudget: 50)
        XCTAssertLessThan(kept.count, msgs.count)
        XCTAssertEqual(kept.count + dropped, msgs.count)
        XCTAssertLessThanOrEqual(TokenEstimator.estimate(kept), 50)
    }

    func testTrimHistoryAlwaysKeepsAtLeastOne() {
        let msgs = [Message(role: .user, content: String(repeating: "x", count: 1000))]
        let (kept, _) = ContextAssembler.trimHistory(msgs, tokenBudget: 10)
        XCTAssertEqual(kept.count, 1)
    }

    func testAssembleMarksTruncatedWhenHistoryDropped() async {
        let big = (0..<20).map { i in
            Message(role: i.isMultiple(of: 2) ? .user : .assistant,
                    content: String(repeating: "x", count: 400))
        }
        let assembler = ContextAssembler(
            mode: .chat,
            budget: ContextBudget(totalTokens: 200, responseReserve: 0, memoryReserve: 0, toolsReserve: 0)
        )
        let ctx = await assembler.assemble(messages: big, memoryQuery: "")
        XCTAssertTrue(ctx.truncated)
        XCTAssertGreaterThan(ctx.droppedCount, 0)
    }

    // MARK: - Budget

    func testContextBudgetReservesDeductFromAvailable() {
        let b = ContextBudget(
            totalTokens: 100_000,
            responseReserve: 4_000,
            memoryReserve: 4_000,
            toolsReserve: 2_000
        )
        XCTAssertEqual(b.availableForContext, 90_000)
    }

    func testForModelReturnsExpectedBudgets() {
        XCTAssertEqual(
            ContextBudget.forModel(ModelCatalog.anthropic[0]).totalTokens,
            200_000
        )
        XCTAssertEqual(
            ContextBudget.forModel(ModelCatalog.openai[0]).totalTokens,
            128_000
        )
    }
}

// MARK: - Stub retriever

private struct StubMemoryRetriever: MemoryRetriever {
    let snippets: [MemorySnippet]
    func retrieve(query: String, limit: Int) async throws -> [MemorySnippet] {
        Array(snippets.prefix(limit))
    }
}

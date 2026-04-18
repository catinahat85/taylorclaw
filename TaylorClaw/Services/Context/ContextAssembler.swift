import Foundation

/// Everything a provider needs to make a single request, after the assembler
/// has applied mode, budget, memory retrieval, and history trimming.
struct AssembledContext: Sendable {
    let systemPrompt: String
    let messages: [Message]
    let tools: [MCPTool]
    let memorySnippets: [MemorySnippet]
    let estimatedTokens: Int
    let budget: ContextBudget
    let droppedCount: Int

    var truncated: Bool { droppedCount > 0 }
}

/// Produces an `AssembledContext` from a conversation plus policy inputs.
///
/// Chat mode is a straight pass-through: no tools, no memory, only history
/// trimming to fit the budget. Agent mode adds memory retrieval and tool
/// schemas. The assembler is deliberately stateless — callers construct
/// one per request.
struct ContextAssembler: Sendable {
    let mode: ChatMode
    let budget: ContextBudget
    let userSystemPrompt: String?
    let tools: [MCPTool]
    let memoryRetriever: any MemoryRetriever
    let memoryLimit: Int

    init(
        mode: ChatMode,
        budget: ContextBudget,
        userSystemPrompt: String? = nil,
        tools: [MCPTool] = [],
        memoryRetriever: any MemoryRetriever = NoMemoryRetriever(),
        memoryLimit: Int = 5
    ) {
        self.mode = mode
        self.budget = budget
        self.userSystemPrompt = userSystemPrompt
        self.tools = tools
        self.memoryRetriever = memoryRetriever
        self.memoryLimit = memoryLimit
    }

    /// Build an `AssembledContext` for a pending request.
    ///
    /// - Parameters:
    ///   - messages: The full conversation history up to and including the
    ///     user's latest message.
    ///   - memoryQuery: The text to search memory against — typically the
    ///     latest user message. Empty string skips retrieval.
    func assemble(messages: [Message], memoryQuery: String) async -> AssembledContext {
        let snippets: [MemorySnippet]
        if mode == .agent, !memoryQuery.isEmpty {
            snippets = (try? await memoryRetriever.retrieve(
                query: memoryQuery, limit: memoryLimit
            )) ?? []
        } else {
            snippets = []
        }

        let promptBuilder = SystemPromptBuilder(
            mode: mode,
            userTemplate: userSystemPrompt,
            tools: tools,
            memorySnippets: snippets
        )
        let systemPrompt = promptBuilder.build()

        let promptTokens = TokenEstimator.estimate(systemPrompt)
        let availableForHistory = max(0, budget.availableForContext - promptTokens)

        let (kept, dropped) = Self.trimHistory(messages, tokenBudget: availableForHistory)
        let toolsOut = (mode == .agent) ? tools : []

        let total = promptTokens
            + TokenEstimator.estimate(kept)
            + TokenEstimator.estimate(toolsOut)

        return AssembledContext(
            systemPrompt: systemPrompt,
            messages: kept,
            tools: toolsOut,
            memorySnippets: snippets,
            estimatedTokens: total,
            budget: budget,
            droppedCount: dropped
        )
    }

    // MARK: - History trimming

    /// Drops oldest messages until the history fits `tokenBudget`.
    ///
    /// Always preserves the last message (the user's pending prompt) plus
    /// one paired assistant turn when present.
    static func trimHistory(_ messages: [Message], tokenBudget: Int) -> (kept: [Message], dropped: Int) {
        guard !messages.isEmpty else { return ([], 0) }
        var kept = messages
        var dropped = 0
        // Minimum we preserve: the final message. If it's a user message,
        // that's the new prompt. Always keep at least 1.
        while TokenEstimator.estimate(kept) > tokenBudget && kept.count > 1 {
            kept.removeFirst()
            dropped += 1
        }
        return (kept, dropped)
    }
}

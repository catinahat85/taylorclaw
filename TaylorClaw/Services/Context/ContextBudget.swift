import Foundation

/// Context-window accounting for a single request.
///
/// `totalTokens` is the model's hard limit. The three "reserve" fields carve
/// out space for the model's response, retrieved memory, and tool schemas
/// so they don't get evicted by a long chat history.
struct ContextBudget: Sendable, Hashable {
    let totalTokens: Int
    let responseReserve: Int
    let memoryReserve: Int
    let toolsReserve: Int

    /// Tokens left over for system prompt + message history after reserves.
    var availableForContext: Int {
        max(0, totalTokens - responseReserve - memoryReserve - toolsReserve)
    }

    init(
        totalTokens: Int,
        responseReserve: Int = 4_000,
        memoryReserve: Int = 4_000,
        toolsReserve: Int = 2_000
    ) {
        self.totalTokens = totalTokens
        self.responseReserve = responseReserve
        self.memoryReserve = memoryReserve
        self.toolsReserve = toolsReserve
    }

    /// Conservative default used when a provider doesn't publish a limit.
    static let fallback = ContextBudget(totalTokens: 32_000)

    /// Per-model budgets. Values reflect published context windows in
    /// early 2026; adjust as providers bump limits.
    static func forModel(_ model: LLMModel) -> ContextBudget {
        switch model.provider {
        case .anthropic:
            // Claude 4.x series: 200k window.
            return ContextBudget(totalTokens: 200_000)
        case .openai:
            // GPT-5 / GPT-4.1: 128k–1M depending on variant. Stay safe at 128k.
            return ContextBudget(totalTokens: 128_000)
        case .gemini:
            // Gemini 2.5 Pro: 1M, Flash: 1M. Reserve more for response.
            return ContextBudget(
                totalTokens: 1_000_000,
                responseReserve: 8_000
            )
        case .ollama:
            // Local models vary widely; be conservative.
            return ContextBudget(totalTokens: 8_000, responseReserve: 1_500)
        case .openrouter:
            // Unknown until we fetch model metadata; use a safe midpoint.
            return ContextBudget(totalTokens: 64_000)
        }
    }
}

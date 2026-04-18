import Foundation

/// Rough token estimator.
///
/// Uses the standard chars-per-token heuristic (`chars / 4`) that BPE
/// tokenizers approximate for English prose. It is intentionally provider-
/// agnostic and deterministic — exact accounting happens server-side. The
/// goal here is budget decisions, not billing.
///
/// Rule of thumb: overestimate slightly so we don't blow the model's
/// context window when we're close.
enum TokenEstimator {
    /// Estimate token count for a string.
    static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let chars = text.unicodeScalars.count
        return max(1, (chars + 3) / 4)
    }

    /// Estimate tokens for a single message, accounting for role overhead.
    static func estimate(_ message: Message) -> Int {
        // Role markers (<|user|> etc.) and framing add ~4 tokens per message
        // in most chat templates.
        estimate(message.content) + 4
    }

    /// Estimate total tokens for an array of messages.
    static func estimate(_ messages: [Message]) -> Int {
        messages.reduce(0) { $0 + estimate($1) }
    }

    /// Estimate tokens for a tool definition (name + description + schema JSON).
    static func estimate(_ tool: MCPTool) -> Int {
        var count = estimate(tool.name)
        if let d = tool.description { count += estimate(d) }
        if let schema = tool.inputSchema,
           let data = try? JSONEncoder().encode(schema),
           let str = String(data: data, encoding: .utf8) {
            count += estimate(str)
        }
        return count + 4
    }

    static func estimate(_ tools: [MCPTool]) -> Int {
        tools.reduce(0) { $0 + estimate($1) }
    }
}

import Foundation

struct LLMModel: Identifiable, Hashable, Codable, Sendable {
    let provider: ProviderID
    let id: String
    let displayName: String

    var qualifiedID: String { "\(provider.rawValue):\(id)" }
}

enum ModelCatalog {
    static let anthropic: [LLMModel] = [
        LLMModel(provider: .anthropic, id: "claude-opus-4-7", displayName: "Claude Opus 4.7"),
        LLMModel(provider: .anthropic, id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
        LLMModel(provider: .anthropic, id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5")
    ]

    static let openai: [LLMModel] = [
        LLMModel(provider: .openai, id: "gpt-5", displayName: "GPT-5"),
        LLMModel(provider: .openai, id: "gpt-5-mini", displayName: "GPT-5 mini"),
        LLMModel(provider: .openai, id: "gpt-4.1", displayName: "GPT-4.1")
    ]

    static let gemini: [LLMModel] = [
        LLMModel(provider: .gemini, id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
        LLMModel(provider: .gemini, id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash")
    ]

    static func staticModels(for provider: ProviderID) -> [LLMModel] {
        switch provider {
        case .anthropic: anthropic
        case .openai: openai
        case .gemini: gemini
        case .ollama: []
        case .openrouter: []
        }
    }

    static let defaultModel = LLMModel(
        provider: .anthropic,
        id: "claude-opus-4-7",
        displayName: "Claude Opus 4.7"
    )
}

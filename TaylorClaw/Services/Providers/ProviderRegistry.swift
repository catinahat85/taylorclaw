import Foundation

struct ProviderRegistry: Sendable {
    static let shared = ProviderRegistry()

    let anthropic: AnthropicProvider
    let openai: OpenAIProvider
    let gemini: GeminiProvider
    let ollama: OllamaProvider
    let openrouter: OpenRouterProvider

    init(
        anthropic: AnthropicProvider = AnthropicProvider(),
        openai: OpenAIProvider = OpenAIProvider(),
        gemini: GeminiProvider = GeminiProvider(),
        ollama: OllamaProvider = OllamaProvider(),
        openrouter: OpenRouterProvider = OpenRouterProvider()
    ) {
        self.anthropic = anthropic
        self.openai = openai
        self.gemini = gemini
        self.ollama = ollama
        self.openrouter = openrouter
    }

    func provider(for id: ProviderID) -> any LLMProvider {
        switch id {
        case .anthropic: anthropic
        case .openai: openai
        case .gemini: gemini
        case .ollama: ollama
        case .openrouter: openrouter
        }
    }
}

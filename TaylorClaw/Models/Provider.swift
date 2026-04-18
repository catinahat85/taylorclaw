import Foundation

enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case anthropic
    case openai
    case gemini
    case ollama
    case openrouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .ollama: "Ollama"
        case .openrouter: "OpenRouter"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama: false
        default: true
        }
    }

    var consoleURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .ollama: URL(string: "https://ollama.com/download")
        case .openrouter: URL(string: "https://openrouter.ai/keys")
        }
    }
}

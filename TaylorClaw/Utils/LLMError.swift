import Foundation

enum LLMError: LocalizedError, Sendable {
    case missingAPIKey(ProviderID)
    case invalidResponse(status: Int, body: String?)
    case invalidURL
    case decodingFailure(String)
    case network(String)
    case cancelled
    case providerUnavailable(ProviderID, reason: String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "No API key configured for \(provider.displayName). Add one in Settings."
        case .invalidResponse(let status, let body):
            if let body, !body.isEmpty {
                "Provider returned HTTP \(status): \(body)"
            } else {
                "Provider returned HTTP \(status)."
            }
        case .invalidURL:
            "Invalid request URL."
        case .decodingFailure(let detail):
            "Could not decode response: \(detail)"
        case .network(let detail):
            "Network error: \(detail)"
        case .cancelled:
            "Request cancelled."
        case .providerUnavailable(let provider, let reason):
            "\(provider.displayName) unavailable: \(reason)"
        case .unknown(let detail):
            detail
        }
    }
}

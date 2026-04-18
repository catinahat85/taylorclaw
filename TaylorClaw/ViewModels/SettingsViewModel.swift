import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    struct ProviderStatus: Equatable {
        enum State: Equatable {
            case idle
            case testing
            case success
            case failure(String)
        }
        var hasKey: Bool = false
        var state: State = .idle
    }

    var keyInputs: [ProviderID: String] = [:]
    var statuses: [ProviderID: ProviderStatus] = [:]
    var ollamaModels: [LLMModel] = []

    private let keychain: KeychainStore
    private let registry: ProviderRegistry

    init(keychain: KeychainStore = .shared, registry: ProviderRegistry = .shared) {
        self.keychain = keychain
        self.registry = registry
        for provider in ProviderID.allCases {
            statuses[provider] = ProviderStatus()
            keyInputs[provider] = ""
        }
    }

    func load() async {
        for provider in ProviderID.allCases where provider.requiresAPIKey {
            let has = await keychain.hasKey(for: provider)
            statuses[provider]?.hasKey = has
        }
        await refreshOllama()
    }

    func save(_ key: String, for provider: ProviderID) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await keychain.save(trimmed, for: provider)
            statuses[provider]?.hasKey = true
            keyInputs[provider] = ""
            statuses[provider]?.state = .idle
        } catch {
            statuses[provider]?.state = .failure(error.localizedDescription)
        }
    }

    func remove(_ provider: ProviderID) async {
        do {
            try await keychain.delete(for: provider)
            statuses[provider]?.hasKey = false
            statuses[provider]?.state = .idle
        } catch {
            statuses[provider]?.state = .failure(error.localizedDescription)
        }
    }

    func testConnection(_ provider: ProviderID) async {
        statuses[provider]?.state = .testing
        do {
            try await registry.provider(for: provider).testConnection()
            statuses[provider]?.state = .success
        } catch let error as LLMError {
            statuses[provider]?.state = .failure(error.errorDescription ?? "Failed")
        } catch {
            statuses[provider]?.state = .failure(error.localizedDescription)
        }
    }

    func refreshOllama() async {
        do {
            ollamaModels = try await registry.ollama.availableModels()
            statuses[.ollama]?.hasKey = !ollamaModels.isEmpty
            statuses[.ollama]?.state = .idle
        } catch let error as LLMError {
            ollamaModels = []
            statuses[.ollama]?.hasKey = false
            statuses[.ollama]?.state = .failure(error.errorDescription ?? "Unavailable")
        } catch {
            ollamaModels = []
            statuses[.ollama]?.hasKey = false
            statuses[.ollama]?.state = .failure(error.localizedDescription)
        }
    }

    func hasAnyConfiguredProvider() -> Bool {
        for (provider, status) in statuses {
            if provider == .ollama {
                if !ollamaModels.isEmpty { return true }
            } else if status.hasKey {
                return true
            }
        }
        return false
    }
}

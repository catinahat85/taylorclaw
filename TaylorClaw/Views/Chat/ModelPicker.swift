import SwiftUI

struct ModelPicker: View {
    @Binding var selected: LLMModel
    let availableProviders: Set<ProviderID>
    let ollamaModels: [LLMModel]
    let openRouterModels: [LLMModel]

    var body: some View {
        Menu {
            ForEach(ProviderID.allCases) { provider in
                let models = allModels(for: provider)
                if !models.isEmpty && availableProviders.contains(provider) {
                    Section(provider.displayName) {
                        ForEach(models) { model in
                            Button {
                                selected = model
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                    if model.qualifiedID == selected.qualifiedID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(providerColor(selected.provider))
                    .frame(width: 8, height: 8)
                Text(selected.displayName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func allModels(for provider: ProviderID) -> [LLMModel] {
        switch provider {
        case .ollama: ollamaModels
        case .openrouter: openRouterModels
        default: ModelCatalog.staticModels(for: provider)
        }
    }

    private func providerColor(_ provider: ProviderID) -> Color {
        switch provider {
        case .anthropic: .orange
        case .openai: .green
        case .gemini: .blue
        case .ollama: .purple
        case .openrouter: .pink
        }
    }
}

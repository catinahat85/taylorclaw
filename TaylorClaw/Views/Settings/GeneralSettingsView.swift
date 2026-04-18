import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var preferences: Preferences
    @Bindable var settingsViewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Default model") {
                Picker(
                    "Default",
                    selection: Binding(
                        get: { preferences.defaultModelQualifiedID },
                        set: { preferences.defaultModelQualifiedID = $0 }
                    )
                ) {
                    ForEach(ProviderID.allCases) { provider in
                        let models = allModels(for: provider)
                        if !models.isEmpty {
                            Section(provider.displayName) {
                                ForEach(models) { model in
                                    Text(model.displayName).tag(model.qualifiedID)
                                }
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Appearance") {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { preferences.appearance },
                        set: { preferences.appearance = $0 }
                    )
                ) {
                    ForEach(AppearanceOverride.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Text("Taylor Claw v0.1 — BYO-key macOS chat client.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func allModels(for provider: ProviderID) -> [LLMModel] {
        switch provider {
        case .ollama: settingsViewModel.ollamaModels
        case .openrouter: preferences.openRouterModelIDs.map {
            LLMModel(provider: .openrouter, id: $0, displayName: $0)
        }
        default: ModelCatalog.staticModels(for: provider)
        }
    }
}

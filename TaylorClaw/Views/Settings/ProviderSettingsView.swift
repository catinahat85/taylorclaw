import SwiftUI

struct ProviderSettingsView: View {
    let provider: ProviderID
    @Bindable var viewModel: SettingsViewModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section(header: Text(provider.displayName).font(.headline)) {
                if provider.requiresAPIKey {
                    apiKeySection
                } else {
                    ollamaSection
                }

                if provider == .openrouter {
                    openRouterModelsSection
                }

                if let url = provider.consoleURL {
                    Link("Open \(provider.displayName) console", destination: url)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var apiKeySection: some View {
        let status = viewModel.statuses[provider] ?? SettingsViewModel.ProviderStatus()
        VStack(alignment: .leading, spacing: 10) {
            if status.hasKey {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Key saved in Keychain")
                        .font(.callout)
                    Spacer()
                    Button("Remove") {
                        Task { await viewModel.remove(provider) }
                    }
                }
            }

            SecureField(
                status.hasKey ? "Replace API key" : "Paste API key",
                text: Binding(
                    get: { viewModel.keyInputs[provider] ?? "" },
                    set: { viewModel.keyInputs[provider] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save") {
                    Task {
                        await viewModel.save(viewModel.keyInputs[provider] ?? "", for: provider)
                    }
                }
                .disabled((viewModel.keyInputs[provider] ?? "").isEmpty)

                Button("Test connection") {
                    Task { await viewModel.testConnection(provider) }
                }
                .disabled(!status.hasKey)

                statusView(status.state)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        let status = viewModel.statuses[.ollama] ?? SettingsViewModel.ProviderStatus()
        VStack(alignment: .leading, spacing: 10) {
            Text("Ollama runs locally. Taylor Claw auto-detects it at http://localhost:11434.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Refresh models") {
                    Task { await viewModel.refreshOllama() }
                }
                statusView(status.state)
                Spacer()
            }

            if !viewModel.ollamaModels.isEmpty {
                Text("Detected models")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(viewModel.ollamaModels) { model in
                    HStack {
                        Image(systemName: "cube")
                        Text(model.displayName)
                        Spacer()
                    }
                    .font(.callout)
                }
            } else if case .failure = status.state {
                Text("No models detected. Is Ollama running? `ollama serve` in Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var openRouterModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model IDs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("One per line. Example: anthropic/claude-opus-4 or openai/gpt-5.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { preferences.openRouterModelIDs.joined(separator: "\n") },
                set: { preferences.openRouterModelIDs = $0.split(separator: "\n").map(String.init) }
            ))
            .frame(minHeight: 90)
            .font(.system(.callout, design: .monospaced))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func statusView(_ state: SettingsViewModel.ProviderStatus.State) -> some View {
        switch state {
        case .idle: EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Testing…").font(.caption)
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        case .failure(let detail):
            Label(detail, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption).lineLimit(2)
        }
    }
}

import SwiftUI

struct SettingsWindow: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable var documentsViewModel: DocumentsViewModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences, settingsViewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }

            ForEach(ProviderID.allCases) { provider in
                ProviderSettingsView(
                    provider: provider,
                    viewModel: viewModel,
                    preferences: preferences
                )
                .tabItem { Label(provider.displayName, systemImage: icon(for: provider)) }
            }

            DocumentsSettingsView(viewModel: documentsViewModel)
                .tabItem { Label("Documents", systemImage: "doc.text") }

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 460)
        .task { await viewModel.load() }
    }

    private func icon(for provider: ProviderID) -> String {
        switch provider {
        case .anthropic: "brain"
        case .openai: "bubble.left.and.bubble.right"
        case .gemini: "sparkles"
        case .ollama: "desktopcomputer"
        case .openrouter: "arrow.triangle.branch"
        }
    }
}

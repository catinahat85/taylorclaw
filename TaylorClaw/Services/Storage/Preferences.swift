import Foundation
import SwiftUI

enum AppearanceOverride: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("defaultModelQualifiedID") var defaultModelQualifiedID: String =
        ModelCatalog.defaultModel.qualifiedID

    @AppStorage("appearance") private var appearanceRaw: String = AppearanceOverride.system.rawValue

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    @AppStorage("hasSkippedRuntimeInstall") var hasSkippedRuntimeInstall: Bool = false

    @AppStorage("openRouterModelIDs") private var openRouterModelIDsRaw: String = ""

    var appearance: AppearanceOverride {
        get { AppearanceOverride(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var openRouterModelIDs: [String] {
        get {
            openRouterModelIDsRaw
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            openRouterModelIDsRaw = newValue.joined(separator: "\n")
        }
    }

    var defaultModel: LLMModel {
        parseQualifiedID(defaultModelQualifiedID) ?? ModelCatalog.defaultModel
    }

    private func parseQualifiedID(_ qualified: String) -> LLMModel? {
        let parts = qualified.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let providerID = ProviderID(rawValue: parts[0]) else { return nil }
        let modelID = parts[1]
        if let existing = ModelCatalog.staticModels(for: providerID).first(where: { $0.id == modelID }) {
            return existing
        }
        return LLMModel(provider: providerID, id: modelID, displayName: modelID)
    }
}

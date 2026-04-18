import SwiftUI

@main
struct TaylorClawApp: App {
    @StateObject private var preferences = Preferences.shared
    @State private var listViewModel = ConversationListViewModel()
    @State private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        Window("Taylor Claw", id: "main") {
            MainWindow(
                listViewModel: listViewModel,
                settingsViewModel: settingsViewModel,
                preferences: preferences
            )
            .frame(minWidth: 600, minHeight: 500)
            .preferredColorScheme(preferences.appearance.colorScheme)
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    listViewModel.newConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Clear Conversation") {
                    guard let convo = listViewModel.selected else { return }
                    Task {
                        var cleared = convo
                        cleared.messages.removeAll()
                        cleared.title = "New Conversation"
                        try? await ConversationStore.shared.upsert(cleared)
                        await listViewModel.reload()
                    }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(listViewModel.selected == nil)
            }
        }

        Settings {
            SettingsWindow(viewModel: settingsViewModel, preferences: preferences)
                .preferredColorScheme(preferences.appearance.colorScheme)
        }
    }
}

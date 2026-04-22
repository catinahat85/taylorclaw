import SwiftUI

@main
struct TaylorClawApp: App {
    @StateObject private var preferences = Preferences.shared
    @State private var listViewModel = ConversationListViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var documentsViewModel = DocumentsViewModel()
    @State private var runtimeManager = RuntimeManager.shared
    @State private var memoryViewModel = MemoryBrowserViewModel()
    @State private var showRuntimeSheet = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Taylor Claw", id: "main") {
            MainWindow(
                listViewModel: listViewModel,
                settingsViewModel: settingsViewModel,
                documentsViewModel: documentsViewModel,
                preferences: preferences
            )
            .frame(minWidth: 600, minHeight: 500)
            .preferredColorScheme(preferences.appearance.colorScheme)
            .sheet(isPresented: $showRuntimeSheet) {
                RuntimeInstallSheet(manager: runtimeManager) {
                    preferences.hasSkippedRuntimeInstall = true
                }
            }
            .task {
                // Give RuntimeManager time to load its manifest from disk.
                try? await Task.sleep(for: .milliseconds(200))
                if !runtimeManager.isInstalled && !preferences.hasSkippedRuntimeInstall {
                    showRuntimeSheet = true
                }
            }
        }
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    listViewModel.newConversation(mode: preferences.defaultChatMode)
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
            CommandGroup(after: .windowArrangement) {
                Button("Memory Browser") {
                    openWindow(id: "memory")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Window("Memory Browser", id: "memory") {
            MemoryBrowserView(viewModel: memoryViewModel)
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(preferences.appearance.colorScheme)
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsWindow(
                viewModel: settingsViewModel,
                documentsViewModel: documentsViewModel,
                preferences: preferences
            )
            .preferredColorScheme(preferences.appearance.colorScheme)
        }
    }
}

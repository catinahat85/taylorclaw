import SwiftUI

/// Form for creating or editing a single `MCPServerConfig` entry.
struct MCPServerEditorSheet: View {
    let target: MCPServersSettingsView.EditorTarget
    let existingNames: Set<String>
    let onSave: (MCPServerConfig) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var command: String = ""
    @State private var argsText: String = ""
    @State private var envEntries: [EnvEntry] = []
    @State private var cwd: String = ""
    @State private var autoStart: Bool = true
    @State private var validationError: String?

    /// Original name when editing, so we can allow "keep same name" without
    /// tripping the duplicate check.
    private let originalName: String

    init(
        target: MCPServersSettingsView.EditorTarget,
        existingNames: Set<String>,
        onSave: @escaping (MCPServerConfig) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.existingNames = existingNames
        self.onSave = onSave
        self.onCancel = onCancel
        switch target {
        case .create(let c):
            _name = State(initialValue: c.name)
            _command = State(initialValue: c.command)
            _argsText = State(initialValue: c.args.joined(separator: "\n"))
            _envEntries = State(initialValue: c.env.sorted { $0.key < $1.key }.map {
                EnvEntry(key: $0.key, value: $0.value)
            })
            _cwd = State(initialValue: c.cwd ?? "")
            _autoStart = State(initialValue: c.autoStart)
            self.originalName = ""
        case .edit(let oldName, let c):
            _name = State(initialValue: c.name)
            _command = State(initialValue: c.command)
            _argsText = State(initialValue: c.args.joined(separator: "\n"))
            _envEntries = State(initialValue: c.env.sorted { $0.key < $1.key }.map {
                EnvEntry(key: $0.key, value: $0.value)
            })
            _cwd = State(initialValue: c.cwd ?? "")
            _autoStart = State(initialValue: c.autoStart)
            self.originalName = oldName
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 8)

            Form {
                Section("Identity") {
                    TextField("Name", text: $name, prompt: Text("e.g. brave-search"))
                    TextField("Command", text: $command, prompt: Text("npx / uvx / /path/to/binary"))
                }

                Section {
                    TextEditor(text: $argsText)
                        .font(.body.monospaced())
                        .frame(minHeight: 70)
                } header: {
                    Text("Arguments")
                } footer: {
                    Text("One per line. Quoting is not applied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Environment") {
                    ForEach($envEntries) { entry in
                        HStack {
                            TextField("KEY", text: entry.key)
                                .font(.body.monospaced())
                                .autocorrectionDisabled()
                                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
                            TextField("value", text: entry.value)
                                .autocorrectionDisabled()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                let id = entry.wrappedValue.id
                                envEntries.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Variable") {
                        envEntries.append(EnvEntry(key: "", value: ""))
                    }
                }

                Section("Options") {
                    TextField("Working Directory (optional)", text: $cwd)
                    Toggle("Start automatically when Taylor Claw launches", isOn: $autoStart)
                }

                if let msg = validationError {
                    Section {
                        Text(msg).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") { attemptSave() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520)
    }

    private var title: String {
        switch target {
        case .create:   return "Add MCP Server"
        case .edit:     return "Edit MCP Server"
        }
    }

    private func attemptSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Name is required."
            return
        }
        guard !trimmedCmd.isEmpty else {
            validationError = "Command is required."
            return
        }
        if trimmedCmd.contains("=") && trimmedCmd.contains(" ") {
            validationError = "Command should be only the executable (e.g. 'npx'). Put API keys in the Environment section."
            return
        }
        if trimmedName != originalName && existingNames.contains(trimmedName) {
            validationError = "A server named '\(trimmedName)' already exists."
            return
        }

        let args = argsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var envDict: [String: String] = [:]
        for entry in envEntries {
            let k = entry.key.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { continue }
            envDict[k] = entry.value
        }

        let trimmedCwd = cwd.trimmingCharacters(in: .whitespaces)
        let config = MCPServerConfig(
            name: trimmedName,
            command: trimmedCmd,
            args: args,
            env: envDict,
            cwd: trimmedCwd.isEmpty ? nil : trimmedCwd,
            autoStart: autoStart
        )
        onSave(config)
        dismiss()
    }

    private struct EnvEntry: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }
}

import SwiftUI

struct AdvancedSettingsView: View {
    @State private var manager = RuntimeManager.shared
    @State private var diskUsage: String = "…"
    @State private var latestVersion: String? = nil
    @State private var showReinstallConfirm = false
    @State private var showUninstallConfirm = false
    @State private var deleteMemoryOnUninstall = false

    var body: some View {
        Form {
            runtimeSection
            if manager.isInstalled {
                updateSection
            }
            dangerSection
        }
        .formStyle(.grouped)
        .task { await refreshInfo() }
    }

    // MARK: - Runtime Status

    private var runtimeSection: some View {
        Section("Python Runtime") {
            switch manager.state {
            case .loading:
                LabeledContent("Status") { ProgressView().controlSize(.small) }

            case .notInstalled:
                LabeledContent("Status") {
                    Text("Not installed")
                        .foregroundStyle(.secondary)
                }
                Button("Install Runtime…") {
                    RuntimeManager.shared.install()
                }

            case .installing(let phase):
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(phase.label).foregroundStyle(.secondary)
                    }
                }
                Button("Cancel") { manager.cancelInstall() }
                    .foregroundStyle(.red)

            case .installed(let manifest):
                LabeledContent("Python", value: manifest.pythonVersion)
                LabeledContent("MemPalace", value: manifest.mempalaceVersion)
                LabeledContent("ChromaDB", value: manifest.chromadbVersion)
                LabeledContent("FastEmbed", value: manifest.fastembedVersion)
                LabeledContent("Installed", value: manifest.installDate
                    .formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Disk Usage", value: diskUsage)
                Button("Open Runtime Folder") { openRuntimeFolder() }

            case .failed(let msg):
                LabeledContent("Status") {
                    Text("Failed: \(msg)")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Button("Retry Install") { manager.install() }
                Button("Open Install Log") { openLog() }
            }
        }
    }

    // MARK: - Update

    private var updateSection: some View {
        Section("MemPalace") {
            if let latest = latestVersion,
               latest != manager.manifest?.mempalaceVersion {
                LabeledContent("Update Available") {
                    HStack {
                        Text(latest)
                            .foregroundStyle(.secondary)
                        Button("Update") {
                            Task { await manager.updateMemPalace() }
                        }
                        .buttonStyle(.link)
                    }
                }
            } else {
                LabeledContent("Version") {
                    HStack {
                        Text(manager.manifest?.mempalaceVersion ?? "—")
                            .foregroundStyle(.secondary)
                        Button("Check for Updates") {
                            Task { latestVersion = await manager.checkForUpdates() }
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            LabeledContent("Runtime Trace") {
                HStack(spacing: 12) {
                    Text("mcp-mempalace.log")
                        .foregroundStyle(.secondary)
                    Button("Open Log File") {
                        openMemPalaceLog()
                    }
                    .buttonStyle(.link)
                    Button("Open Folder") {
                        NSWorkspace.shared.open(RuntimeConstants.appSupport)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        Section("Manage") {
            Button("Reinstall Runtime…") {
                showReinstallConfirm = true
            }
            .confirmationDialog(
                "Reinstall Python Runtime?",
                isPresented: $showReinstallConfirm,
                titleVisibility: .visible
            ) {
                Button("Reinstall", role: .destructive) {
                    Task { await manager.reinstall() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete the current runtime and re-download Python (~100 MB). Your memory data will be preserved.")
            }

            Button("Uninstall Runtime…") {
                showUninstallConfirm = true
            }
            .foregroundStyle(.red)
            .confirmationDialog(
                "Uninstall Python Runtime?",
                isPresented: $showUninstallConfirm,
                titleVisibility: .visible
            ) {
                Button("Uninstall", role: .destructive) {
                    Task { await manager.uninstall(deleteMemory: deleteMemoryOnUninstall) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                VStack {
                    Text("This removes the Python runtime and packages. Agent mode will be disabled.")
                    Toggle("Also delete memory data", isOn: $deleteMemoryOnUninstall)
                }
            }
        }
    }

    // MARK: - Actions

    private func refreshInfo() async {
        diskUsage = await manager.runtimeDiskUsage()
        if manager.isInstalled {
            latestVersion = await manager.checkForUpdates()
        }
    }

    private func openRuntimeFolder() {
        NSWorkspace.shared.open(RuntimeConstants.runtimeDir)
    }

    private func openLog() {
        NSWorkspace.shared.open(RuntimeConstants.installLogURL)
    }

    private func openMemPalaceLog() {
        let logURL = RuntimeConstants.appSupport.appendingPathComponent("mcp-mempalace.log")
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
        } else {
            NSWorkspace.shared.open(RuntimeConstants.appSupport)
        }
    }
}

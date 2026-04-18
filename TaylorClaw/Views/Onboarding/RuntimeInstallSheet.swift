import SwiftUI

struct RuntimeInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var manager: RuntimeManager
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up Taylor Claw")
                    .font(.title2.weight(.semibold))
                Text("One-time setup · about 100 MB · your user library only")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .loading, .notInstalled:
            idleBody
        case .installing(let phase):
            installingBody(phase: phase)
        case .installed:
            successBody
        case .failed(let msg):
            failedBody(message: msg)
        }
    }

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
                Agent mode uses **MemPalace** for persistent memory and local document search. \
                This requires a Python runtime installed once into your user library (~100 MB).

                Taylor Claw will **not** run system-wide installs or touch your existing Python.
                """)
            .fixedSize(horizontal: false, vertical: true)

            Label("Installed to: ~/Library/Application Support/TaylorClaw/runtime/",
                  systemImage: "folder")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func installingBody(phase: InstallPhase) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: manager.progress)
                .progressViewStyle(.linear)
                .animation(.easeInOut(duration: 0.3), value: manager.progress)

            HStack {
                Text(phase.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .animation(.default, value: phase.label)
                Spacer()
                Text("\(Int(manager.progress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !manager.logLines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(manager.logLines.enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(height: 100)
                    .onChange(of: manager.logLines.count) { _, _ in
                        proxy.scrollTo(manager.logLines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(20)
    }

    private var successBody: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.green)
            Text("MemPalace is ready")
                .font(.title3.weight(.semibold))
            Text("Agent mode is now available.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func failedBody(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installation failed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Install Log") { openLog() }
                .buttonStyle(.link)
                .font(.subheadline)
        }
        .padding(20)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if case .installing = manager.state {
                Button("Cancel") {
                    manager.cancelInstall()
                }
                .keyboardShortcut(.cancelAction)
            } else if case .installed = manager.state {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else if case .failed = manager.state {
                Button("Not Now") { skip() }
                Spacer()
                Button("Retry") { manager.install() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Not Now") { skip() }
                Spacer()
                Link("Learn More",
                     destination: URL(string: "https://github.com/catinahat85/taylorclaw")!)
                Button("Install Now") { manager.install() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func skip() {
        onSkip()
        dismiss()
    }

    private func openLog() {
        NSWorkspace.shared.open(RuntimeConstants.installLogURL)
    }
}

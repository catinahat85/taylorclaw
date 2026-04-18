import Foundation
import Observation

// MARK: - Value types

struct RuntimeManifest: Codable, Sendable {
    var pythonVersion:    String
    var mempalaceVersion: String
    var chromadbVersion:  String
    var fastembedVersion: String
    var installDate:      Date
    var archiveSHA256:    String
}

enum InstallPhase: Sendable, Equatable {
    case idle
    case checkingDisk
    case downloadingPython
    case verifyingSHA
    case extracting
    case creatingVenv
    case upgradingPip
    case installingPackages
    case initializing
    case smokeTesting

    var label: String {
        switch self {
        case .idle:                 return "Preparing…"
        case .checkingDisk:         return "Checking disk space…"
        case .downloadingPython:    return "Downloading Python (~100 MB)…"
        case .verifyingSHA:         return "Verifying download…"
        case .extracting:           return "Extracting Python…"
        case .creatingVenv:         return "Creating virtual environment…"
        case .upgradingPip:         return "Upgrading pip…"
        case .installingPackages:   return "Installing MemPalace and dependencies…"
        case .initializing:         return "Initialising data directory…"
        case .smokeTesting:         return "Running smoke test…"
        }
    }

    var stepProgress: Double {
        switch self {
        case .idle:                 return 0.02
        case .checkingDisk:         return 0.05
        case .downloadingPython:    return 0.10
        case .verifyingSHA:         return 0.50
        case .extracting:           return 0.55
        case .creatingVenv:         return 0.68
        case .upgradingPip:         return 0.72
        case .installingPackages:   return 0.80
        case .initializing:         return 0.94
        case .smokeTesting:         return 0.97
        }
    }
}

enum RuntimeError: LocalizedError, Sendable {
    case diskFull(requiredBytes: Int64)
    case downloadFailed(String)
    case sha256Mismatch
    case processFailure(code: Int, stderr: String)
    case notInstalled
    case smokeTestFailed(String)

    var errorDescription: String? {
        switch self {
        case .diskFull(let n):
            return "Not enough disk space — need \(n / 1_000_000) MB free."
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .sha256Mismatch:
            return "SHA-256 check failed — the archive may be corrupted. Please try again."
        case .processFailure(let code, _):
            return "A subprocess exited with code \(code)."
        case .notInstalled:
            return "Python runtime is not installed."
        case .smokeTestFailed(let detail):
            return "MemPalace smoke test failed: \(detail)"
        }
    }
}

// MARK: - RuntimeManager

@MainActor
@Observable
final class RuntimeManager {
    static let shared = RuntimeManager()

    enum State: Sendable {
        case loading
        case notInstalled
        case installing(phase: InstallPhase)
        case installed(RuntimeManifest)
        case failed(String)
    }

    var state: State = .loading
    var progress: Double = 0
    var logLines: [String] = []

    private let installer = PythonInstaller()
    private var installTask: Task<Void, Never>?

    var isInstalled: Bool {
        if case .installed = state { return true }
        return false
    }

    var manifest: RuntimeManifest? {
        if case .installed(let m) = state { return m }
        return nil
    }

    private init() {
        Task { await self.loadManifest() }
    }

    // MARK: - Public actions

    func install() {
        guard installTask == nil else { return }
        installTask = Task {
            defer { installTask = nil }
            state = .installing(phase: .idle)
            progress = 0
            logLines = []
            do {
                let manifest = try await installer.install { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.handleInstallerEvent(event)
                    }
                }
                state = .installed(manifest)
                progress = 1.0
            } catch is CancellationError {
                state = .notInstalled
                progress = 0
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
    }

    func uninstall(deleteMemory: Bool = false) async {
        do {
            try await installer.uninstall(deleteMemory: deleteMemory)
            state = .notInstalled
            progress = 0
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reinstall() async {
        await uninstall(deleteMemory: false)
        install()
    }

    func checkForUpdates() async -> String? {
        await installer.latestMempalaceVersion()
    }

    func updateMemPalace() async {
        guard case .installed(var manifest) = state else { return }
        do {
            let newVersion = try await installer.updateMempalace()
            manifest.mempalaceVersion = newVersion
            try await installer.writeManifest(manifest)
            state = .installed(manifest)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func runtimeDiskUsage() async -> String {
        await installer.diskUsageString()
    }

    // MARK: - Private

    private func loadManifest() async {
        guard let m = try? await installer.readManifest() else {
            state = .notInstalled
            return
        }
        state = .installed(m)
    }

    private func handleInstallerEvent(_ event: InstallerEvent) {
        switch event {
        case .phase(let p):
            state = .installing(phase: p)
            progress = p.stepProgress
        case .log(let line):
            logLines.append(line)
        }
    }
}

// MARK: - InstallerEvent (bridge from actor → MainActor)

enum InstallerEvent: Sendable {
    case phase(InstallPhase)
    case log(String)
}

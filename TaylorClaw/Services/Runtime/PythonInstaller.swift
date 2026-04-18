import Foundation
import CryptoKit

// Boxes a non-Sendable Foundation type so it can cross isolation boundaries.
// Safe here because each Box is owned by exactly one task at a time.
private struct Box<T>: @unchecked Sendable { let value: T }

typealias EventCallback = @Sendable (InstallerEvent) -> Void

actor PythonInstaller {

    // MARK: - Install

    func install(onEvent emit: @escaping EventCallback) async throws -> RuntimeManifest {
        emit(.phase(.checkingDisk))
        try checkDiskSpace()

        let fm = FileManager.default
        try fm.createDirectory(at: RuntimeConstants.runtimeDir,
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: RuntimeConstants.appSupport,
                               withIntermediateDirectories: true)

        // 1. SHA256SUMS
        emit(.phase(.downloadingPython))
        emit(.log("Fetching SHA256SUMS from GitHub…"))
        let (sumsData, _) = try await URLSession.shared.data(from: RuntimeConstants.sha256SumsURL)
        let expectedSHA = try parseSHA256(sumsData,
                                         filename: RuntimeConstants.pythonArchiveFilename)
        emit(.log("Expected SHA256: \(expectedSHA)"))

        // 2. Download archive
        emit(.log("Downloading \(RuntimeConstants.pythonArchiveFilename)…"))
        let archiveDest = RuntimeConstants.runtimeDir
            .appendingPathComponent("python-archive.tar.gz")
        if fm.fileExists(atPath: archiveDest.path) {
            try fm.removeItem(at: archiveDest)
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: RuntimeConstants.pythonDownloadURL)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RuntimeError.downloadFailed("Server returned non-2xx status")
            }
            try data.write(to: archiveDest)
            emit(.log("Downloaded \(data.count / 1_000_000) MB."))

            // 3. Verify SHA256 (hash the data already in RAM — free)
            emit(.phase(.verifyingSHA))
            let actualSHA = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
            emit(.log("Actual SHA256:   \(actualSHA)"))
            guard actualSHA == expectedSHA else {
                try? fm.removeItem(at: archiveDest)
                throw RuntimeError.sha256Mismatch
            }
            emit(.log("SHA256 verified."))
        } catch let e as RuntimeError { throw e } catch {
            throw RuntimeError.downloadFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        // 4. Extract
        emit(.phase(.extracting))
        emit(.log("Extracting Python archive…"))
        if fm.fileExists(atPath: RuntimeConstants.pythonDir.path) {
            try fm.removeItem(at: RuntimeConstants.pythonDir)
        }
        try await shell("/usr/bin/tar",
                        "-xzf", archiveDest.path,
                        "-C", RuntimeConstants.runtimeDir.path,
                        emit: emit)
        try normalizePythonDir()
        try fm.removeItem(at: archiveDest)
        emit(.log("Extraction complete."))

        try Task.checkCancellation()

        // 5. Create venv
        emit(.phase(.creatingVenv))
        emit(.log("Creating virtual environment…"))
        try await shell(RuntimeConstants.python3.path,
                        "-m", "venv", RuntimeConstants.venvDir.path,
                        emit: emit)
        emit(.log("Venv ready."))

        // 6. Upgrade pip
        emit(.phase(.upgradingPip))
        try await shell(RuntimeConstants.venvPip.path,
                        "install", "--upgrade", "pip", "--quiet",
                        emit: emit)
        emit(.log("pip upgraded."))

        try Task.checkCancellation()

        // 7. Install packages
        emit(.phase(.installingPackages))
        emit(.log("Installing mempalace \(RuntimeConstants.mempalaceVersion), chromadb \(RuntimeConstants.chromadbVersion), fastembed \(RuntimeConstants.fastembedVersion)…"))
        try await shell(RuntimeConstants.venvPip.path,
                        "install", "--quiet",
                        "mempalace==\(RuntimeConstants.mempalaceVersion)",
                        "chromadb==\(RuntimeConstants.chromadbVersion)",
                        "fastembed==\(RuntimeConstants.fastembedVersion)",
                        emit: emit)
        emit(.log("Packages installed."))

        // 8. Initialise data dir
        emit(.phase(.initializing))
        try fm.createDirectory(at: RuntimeConstants.mempalaceDir,
                               withIntermediateDirectories: true)
        emit(.log("MemPalace data dir: \(RuntimeConstants.mempalaceDir.path)"))

        // 9. Smoke test
        emit(.phase(.smokeTesting))
        emit(.log("Running smoke test…"))
        let result = try await shell(RuntimeConstants.venvPython.path,
                                     "-c", "import mempalace; print('ok')",
                                     emit: emit)
        guard result.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
            throw RuntimeError.smokeTestFailed("unexpected output: \(result)")
        }
        emit(.log("Smoke test passed."))

        // 10. Write install.log
        appendLog("Install completed \(Date())\n")

        // 11. Manifest
        let sha = try computeSHA256OfFile(RuntimeConstants.runtimeDir
            .appendingPathComponent("python-archive.tar.gz"))
        let manifest = RuntimeManifest(
            pythonVersion:    RuntimeConstants.pythonVersion,
            mempalaceVersion: RuntimeConstants.mempalaceVersion,
            chromadbVersion:  RuntimeConstants.chromadbVersion,
            fastembedVersion: RuntimeConstants.fastembedVersion,
            installDate:      Date(),
            archiveSHA256:    sha.isEmpty ? "verified-during-download" : sha
        )
        try await writeManifest(manifest)
        emit(.log("Manifest written. Done."))
        return manifest
    }

    // MARK: - Uninstall

    func uninstall(deleteMemory: Bool) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: RuntimeConstants.runtimeDir.path) {
            try fm.removeItem(at: RuntimeConstants.runtimeDir)
        }
        if deleteMemory, fm.fileExists(atPath: RuntimeConstants.mempalaceDir.path) {
            try fm.removeItem(at: RuntimeConstants.mempalaceDir)
        }
        appendLog("Uninstall completed \(Date()). Memory \(deleteMemory ? "deleted" : "preserved").\n")
    }

    // MARK: - Manifest I/O

    func readManifest() throws -> RuntimeManifest? {
        let url = RuntimeConstants.manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RuntimeManifest.self, from: data)
    }

    func writeManifest(_ manifest: RuntimeManifest) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try FileManager.default.createDirectory(
            at: RuntimeConstants.runtimeDir, withIntermediateDirectories: true)
        try data.write(to: RuntimeConstants.manifestURL, options: .atomic)
    }

    // MARK: - PyPI helpers

    func latestMempalaceVersion() async -> String? {
        guard let url = URL(string: "https://pypi.org/pypi/mempalace/json") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any],
              let version = info["version"] as? String else { return nil }
        return version
    }

    func updateMempalace() async throws -> String {
        try await shell(RuntimeConstants.venvPip.path,
                        "install", "--upgrade", "--quiet", "mempalace",
                        emit: { _ in })
        let output = try await shell(RuntimeConstants.venvPip.path,
                                     "show", "mempalace",
                                     emit: { _ in })
        for line in output.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("Version:") {
                return s.dropFirst("Version:".count)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return RuntimeConstants.mempalaceVersion
    }

    // MARK: - Disk usage

    func diskUsageString() async -> String {
        let url = RuntimeConstants.runtimeDir
        guard FileManager.default.fileExists(atPath: url.path) else { return "Not installed" }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey],
            options: .skipsHiddenFiles
        ) {
            for case let fileURL as URL in enumerator {
                let size = (try? fileURL.resourceValues(forKeys: [.fileAllocatedSizeKey]))?
                    .fileAllocatedSize ?? 0
                total += Int64(size)
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    // MARK: - Private helpers

    private func checkDiskSpace() throws {
        let values = try RuntimeConstants.appSupport
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= RuntimeConstants.requiredDiskBytes else {
            throw RuntimeError.diskFull(requiredBytes: RuntimeConstants.requiredDiskBytes)
        }
    }

    private func parseSHA256(_ data: Data, filename: String) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RuntimeError.downloadFailed("SHA256SUMS not UTF-8")
        }
        for line in text.split(separator: "\n") {
            // Format: "<hash>  <filename>" or "<hash> *<filename>"
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, String(parts.last ?? "").hasSuffix(filename) {
                return String(parts[0])
            }
        }
        throw RuntimeError.downloadFailed("Could not find SHA256 for \(filename)")
    }

    private func normalizePythonDir() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: RuntimeConstants.pythonDir.path) { return }
        // python-build-standalone install_only archives extract to "python/"
        // but some releases use other names — find and rename.
        let contents = try fm.contentsOfDirectory(
            at: RuntimeConstants.runtimeDir, includingPropertiesForKeys: nil)
        guard let candidate = contents.first(where: {
            let n = $0.lastPathComponent
            return n.hasPrefix("python") || n.hasPrefix("cpython")
        }) else {
            throw RuntimeError.downloadFailed(
                "Could not locate Python directory after extraction")
        }
        try fm.moveItem(at: candidate, to: RuntimeConstants.pythonDir)
    }

    @discardableResult
    private func shell(_ executable: String, _ args: String...,
                       emit: @escaping EventCallback) async throws -> String {
        try await shellArgs(executable, args, emit: emit)
    }

    @discardableResult
    private func shellArgs(_ executable: String, _ args: [String],
                           emit: @escaping EventCallback) async throws -> String {
        let outBox = Box(value: Pipe())
        let errBox = Box(value: Pipe())
        let result: String = try await withCheckedThrowingContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            proc.standardOutput = outBox.value
            proc.standardError = errBox.value
            proc.terminationHandler = { p in
                let out = String(
                    data: outBox.value.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? ""
                let err = String(
                    data: errBox.value.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing:
                        RuntimeError.processFailure(
                            code: Int(p.terminationStatus), stderr: err))
                }
            }
            do { try proc.run() } catch { continuation.resume(throwing: error) }
        }
        if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emit(.log(result.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return result
    }

    private func computeSHA256OfFile(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func appendLog(_ line: String) {
        let url = RuntimeConstants.installLogURL
        try? FileManager.default.createDirectory(
            at: RuntimeConstants.appSupport, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data((line).utf8))
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}

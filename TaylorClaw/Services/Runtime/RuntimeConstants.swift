import Foundation

/// Bump these constants to update pinned versions — nothing else needs changing.
enum RuntimeConstants {
    // ── python-build-standalone release 20260414 ───────────────────────
    static let pythonBuildTag = "20260414"
    static let pythonVersion  = "3.10.20"

    static var pythonArchiveFilename: String {
        #if arch(arm64)
        return "cpython-\(pythonVersion)+\(pythonBuildTag)-aarch64-apple-darwin-install_only.tar.gz"
        #else
        return "cpython-\(pythonVersion)+\(pythonBuildTag)-x86_64-apple-darwin-install_only.tar.gz"
        #endif
    }

    static var pythonDownloadURL: URL {
        URL(string: "https://github.com/indygreg/python-build-standalone/releases/download/\(pythonBuildTag)/\(pythonArchiveFilename)")!
    }

    static var sha256SumsURL: URL {
        URL(string: "https://github.com/indygreg/python-build-standalone/releases/download/\(pythonBuildTag)/SHA256SUMS")!
    }

    // ── Pinned PyPI packages ────────────────────────────────────────────
    static let mempalaceVersion = "3.3.0"
    static let chromadbVersion  = "1.5.8"
    static let fastembedVersion = "0.8.0"

    // Minimum free bytes required before starting install (~600 MB covers
    // Python + venv + packages with headroom).
    static let requiredDiskBytes: Int64 = 650_000_000

    // ── Filesystem paths ────────────────────────────────────────────────
    static let appSupport: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaylorClaw")
    }()

    static let runtimeDir:    URL = appSupport.appendingPathComponent("runtime")
    static let pythonDir:     URL = runtimeDir.appendingPathComponent("python")
    static let venvDir:       URL = runtimeDir.appendingPathComponent("venv")
    static let mempalaceDir:  URL = appSupport.appendingPathComponent("mempalace")
    static let manifestURL:   URL = runtimeDir.appendingPathComponent("manifest.json")
    static let installLogURL: URL = appSupport.appendingPathComponent("install.log")

    // Derived executable paths
    static var python3: URL   { pythonDir.appendingPathComponent("bin/python3") }
    static var venvPip: URL   { venvDir.appendingPathComponent("bin/pip") }
    static var venvPython: URL { venvDir.appendingPathComponent("bin/python3") }
}

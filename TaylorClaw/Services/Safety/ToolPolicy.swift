import Foundation

/// Maps tool names to `ToolRisk` values.
///
/// Resolution order:
/// 1. Explicit `blocklist` → `.blocked`.
/// 2. Explicit `overrides[name]` → user-chosen risk.
/// 3. Name-heuristic — keywords like "delete", "write", "get".
/// 4. `defaultRisk` (`.caution` by default — safe fallback).
struct ToolPolicy: Sendable, Hashable {
    let overrides: [String: ToolRisk]
    let blocklist: Set<String>
    let defaultRisk: ToolRisk

    init(
        overrides: [String: ToolRisk] = [:],
        blocklist: Set<String> = [],
        defaultRisk: ToolRisk = .caution
    ) {
        self.overrides = overrides
        self.blocklist = blocklist
        self.defaultRisk = defaultRisk
    }

    func risk(for toolName: String) -> ToolRisk {
        if blocklist.contains(toolName) { return .blocked }
        if let explicit = overrides[toolName] { return explicit }
        if let inferred = Self.heuristicRisk(for: toolName) { return inferred }
        return defaultRisk
    }

    // MARK: - Heuristics

    /// Classify by substring. Checked in order: destructive → caution → safe.
    /// Returns nil when the name doesn't match any keyword.
    static func heuristicRisk(for name: String) -> ToolRisk? {
        let lower = name.lowercased()

        for keyword in destructiveKeywords where lower.contains(keyword) {
            return .destructive
        }
        for keyword in cautionKeywords where lower.contains(keyword) {
            return .caution
        }
        for keyword in safeKeywords where lower.hasPrefix(keyword)
            || lower.contains("_" + keyword) {
            return .safe
        }
        return nil
    }

    private static let destructiveKeywords: [String] = [
        "delete", "remove", "drop", "destroy", "purge", "wipe",
        "format", "uninstall", "revoke", "rmdir",
    ]

    private static let cautionKeywords: [String] = [
        "write", "store", "save", "create", "update", "edit", "set",
        "send", "post", "put", "patch", "exec", "execute", "run",
        "shell", "install", "upload", "move", "rename", "commit",
    ]

    private static let safeKeywords: [String] = [
        "get", "list", "search", "retrieve", "read", "find",
        "query", "describe", "show", "view", "inspect", "lookup",
    ]

    // MARK: - Presets

    /// Default policy bundled with Taylor Claw, with MemPalace tool names
    /// pre-classified so the heuristic's guesses don't override them.
    static let `default` = ToolPolicy(
        overrides: [
            // MemPalace read tools
            "retrieve_memory":   .safe,
            "search_memories":   .safe,
            "list_memories":     .safe,
            "get_memory":        .safe,
            // MemPalace write tools
            "store_memory":      .caution,
            "update_memory":     .caution,
            // MemPalace destructive tools
            "delete_memory":     .destructive,
            "clear_memories":    .destructive,
        ]
    )
}

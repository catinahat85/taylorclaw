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
    ///
    /// Tool names match MemPalace's `mcp_server` exports — the
    /// `mempalace_*` prefix.
    static let `default` = ToolPolicy(
        overrides: [
            // Read — palace introspection + semantic search.
            "mempalace_status":          .safe,
            "mempalace_list_wings":      .safe,
            "mempalace_list_rooms":      .safe,
            "mempalace_get_taxonomy":    .safe,
            "mempalace_search":          .safe,
            "mempalace_check_duplicate": .safe,
            // Write — reversible drawer additions.
            "mempalace_add_drawer":      .caution,
            "mempalace_update_drawer":   .caution,
            // Destructive — drawer / palace removal.
            "mempalace_delete_drawer":   .destructive,
            "mempalace_clear_palace":    .destructive,
        ]
    )
}

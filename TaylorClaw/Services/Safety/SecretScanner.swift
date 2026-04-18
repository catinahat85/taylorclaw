import Foundation

/// Detects common API-key / secret patterns in arbitrary text so we can
/// warn the user before sending them to a remote model or storing them in
/// memory.
///
/// These patterns are intentionally conservative. False positives are
/// better than leaking a real key. Callers should not treat a scan miss
/// as proof that no secret is present.
enum SecretScanner {

    struct Match: Sendable, Hashable {
        let provider: String
        let range: Range<String.Index>
    }

    static func scan(_ text: String) -> [Match] {
        guard !text.isEmpty else { return [] }
        var matches: [Match] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for (provider, regex) in Self.patterns {
            regex.enumerateMatches(in: text, range: full) { result, _, _ in
                guard let r = result,
                      let range = Range(r.range, in: text) else { return }
                matches.append(Match(provider: provider, range: range))
            }
        }
        return matches
    }

    static func contains(_ text: String) -> Bool {
        !scan(text).isEmpty
    }

    /// Replace every matched secret with `replacement`.
    static func redact(_ text: String, replacement: String = "[REDACTED]") -> String {
        let matches = scan(text)
        guard !matches.isEmpty else { return text }
        // Apply replacements from end to start so earlier ranges stay valid.
        let sorted = matches.sorted { $0.range.lowerBound > $1.range.lowerBound }
        var out = text
        for m in sorted {
            out.replaceSubrange(m.range, with: replacement)
        }
        return out
    }

    // MARK: - Patterns

    /// `(provider name, compiled regex)`. Updated when we find new patterns
    /// worth catching — false positives are preferable to leaks here.
    private static let patterns: [(String, NSRegularExpression)] = {
        let defs: [(String, String)] = [
            ("Anthropic", #"sk-ant-[A-Za-z0-9_\-]{20,}"#),
            ("OpenAI",    #"sk-[A-Za-z0-9]{20,}"#),
            ("AWS-AccessKey", #"AKIA[0-9A-Z]{16}"#),
            ("GitHub-PAT", #"gh[pousr]_[A-Za-z0-9]{36,}"#),
            ("Google-API", #"AIza[0-9A-Za-z_\-]{35}"#),
            ("Slack-Token", #"xox[baprs]-[A-Za-z0-9-]{10,}"#),
            ("JWT", #"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#),
        ]
        return defs.compactMap { name, pattern in
            guard let rx = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (name, rx)
        }
    }()
}

import Foundation

/// Splits document text into overlapping chunks suitable for embedding.
///
/// Strategy: paragraph-aware greedy packing.
///   1. Split on blank lines to get paragraphs.
///   2. Greedily concatenate paragraphs until adding another would exceed
///      `targetSize`.
///   3. Start the next chunk with the last `overlap` characters of the
///      previous one so embeddings keep some local context.
///   4. If a single paragraph is longer than `targetSize`, hard-split it.
struct DocumentChunker: Sendable, Hashable {
    let targetSize: Int
    let overlap: Int

    init(targetSize: Int = 1_000, overlap: Int = 120) {
        precondition(targetSize > 0, "targetSize must be positive")
        precondition(overlap >= 0 && overlap < targetSize,
                     "overlap must be ≥ 0 and < targetSize")
        self.targetSize = targetSize
        self.overlap = overlap
    }

    func chunk(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Split into paragraphs, hard-split any that are themselves too long.
        var paragraphs: [String] = []
        for para in trimmed.components(separatedBy: "\n\n") {
            let p = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { continue }
            if p.count <= targetSize {
                paragraphs.append(p)
            } else {
                paragraphs.append(contentsOf: hardSplit(p, size: targetSize))
            }
        }

        // Greedy pack with overlap.
        var chunks: [String] = []
        var current = ""
        for p in paragraphs {
            if current.isEmpty {
                current = p
                continue
            }
            if current.count + 2 + p.count <= targetSize {
                current += "\n\n" + p
            } else {
                chunks.append(current)
                let tail = Self.lastChars(current, count: overlap)
                current = tail.isEmpty ? p : tail + "\n\n" + p
                if current.count > targetSize {
                    // The overlap plus new paragraph exceeds target — drop overlap.
                    current = p
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Helpers

    /// Splits a long string into `size`-sized chunks, preferring whitespace
    /// boundaries near the target cut point.
    private func hardSplit(_ s: String, size: Int) -> [String] {
        var out: [String] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let remaining = s.distance(from: idx, to: s.endIndex)
            if remaining <= size {
                out.append(String(s[idx...]))
                break
            }
            let hardEnd = s.index(idx, offsetBy: size)
            // Look back up to 80 chars for a space to cut cleanly.
            let window = s.index(hardEnd, offsetBy: -min(80, size), limitedBy: idx) ?? idx
            var cut = hardEnd
            if let space = s[window..<hardEnd].lastIndex(where: { $0.isWhitespace }) {
                cut = s.index(after: space)
            }
            out.append(String(s[idx..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
            idx = cut
        }
        return out.filter { !$0.isEmpty }
    }

    private static func lastChars(_ s: String, count: Int) -> String {
        guard count > 0 else { return "" }
        if s.count <= count { return s }
        let start = s.index(s.endIndex, offsetBy: -count)
        return String(s[start...])
    }
}

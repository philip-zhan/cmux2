import Foundation

/// Substring-based ranker tuned for VS Code-style file picker behavior. Faster than
/// Nucleo at file-list scale because it skips the build-an-index step and runs a
/// single linear scan over precomputed lowercased path components.
///
/// Ranking tiers (highest score wins):
///
/// 1. Filename matches the query exactly.
/// 2. Filename starts with the query.
/// 3. Filename contains the query.
/// 4. Full relative path contains the query (used when the user types a directory
///    fragment like `views/cell`).
///
/// Within a tier, shorter strings win — a `Button.swift` whose basename is the query
/// outranks `LargeButtonGroupContainerButton.swift`.
enum CommandPaletteFilePathRanker {
    struct Candidate: Sendable {
        let id: String
        /// Display basename (cased, used for title rendering).
        let fileName: String
        /// Display relative path (cased).
        let relativePath: String
        /// Pre-lowercased basename for matching. Computed once at index time.
        let fileNameLower: String
        /// Pre-lowercased relative path for matching. Computed once at index time.
        let relativePathLower: String
    }

    struct Match: Sendable {
        let id: String
        let score: Int
        /// Original-cased basename. Carried on Match so the JIT materializer in
        /// ContentView doesn't have to look the entry back up by ID.
        let fileName: String
        /// Original-cased relative path.
        let relativePath: String
        /// Indices into the *original-cased* `fileName` for highlight rendering. Empty
        /// when the match is path-only (no basename hit).
        let fileNameMatchIndices: Set<Int>
    }

    /// Highest score awarded — exact filename match.
    private static let tierExact = 4_000_000
    private static let tierStartsWith = 3_000_000
    private static let tierContains = 2_000_000
    private static let tierPathContains = 1_000_000
    /// Shorter strings beat longer ones in the same tier. Clamped so a single character
    /// difference matters but pathological 10k-char paths don't underflow.
    private static let lengthPenaltyCap = 10_000

    static func rank(
        query: String,
        candidates: [Candidate],
        limit: Int,
        shouldCancel: () -> Bool = { false }
    ) -> [Match] {
        guard limit > 0 else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(candidates.prefix(limit)).map {
                Match(
                    id: $0.id,
                    score: 0,
                    fileName: $0.fileName,
                    relativePath: $0.relativePath,
                    fileNameMatchIndices: []
                )
            }
        }
        let needle = trimmed.lowercased()

        var matches: [Match] = []
        matches.reserveCapacity(min(candidates.count, 1024))

        for candidate in candidates {
            if shouldCancel() { break }
            guard let match = Self.scoreCandidate(candidate, needle: needle) else {
                continue
            }
            matches.append(match)
        }

        matches.sort { $0.score > $1.score }
        if matches.count > limit {
            matches.removeLast(matches.count - limit)
        }
        return matches
    }

    private static func scoreCandidate(_ candidate: Candidate, needle: String) -> Match? {
        if let basenameRange = candidate.fileNameLower.range(of: needle) {
            let basenameStart = basenameRange.lowerBound
            let basenameEnd = basenameRange.upperBound
            let penalty = min(candidate.fileNameLower.count, Self.lengthPenaltyCap)
            let score: Int
            if basenameStart == candidate.fileNameLower.startIndex
                && basenameEnd == candidate.fileNameLower.endIndex {
                score = Self.tierExact - penalty
            } else if basenameStart == candidate.fileNameLower.startIndex {
                score = Self.tierStartsWith - penalty
            } else {
                score = Self.tierContains - penalty
            }
            let matchIndices = Self.indicesIntoOriginal(
                lowercased: candidate.fileNameLower,
                original: candidate.fileName,
                range: basenameRange
            )
            return Match(
                id: candidate.id,
                score: score,
                fileName: candidate.fileName,
                relativePath: candidate.relativePath,
                fileNameMatchIndices: matchIndices
            )
        }
        if candidate.relativePathLower.range(of: needle) != nil {
            let penalty = min(candidate.relativePathLower.count, Self.lengthPenaltyCap)
            return Match(
                id: candidate.id,
                score: Self.tierPathContains - penalty,
                fileName: candidate.fileName,
                relativePath: candidate.relativePath,
                fileNameMatchIndices: []
            )
        }
        return nil
    }

    /// Lowercasing can change the unicode-scalar count for some characters (e.g. ß → ss).
    /// In the common ASCII case the offsets line up, so we return character indices into
    /// the original string. For the rare case where they don't, we degrade to an empty
    /// highlight set rather than misaligning the rendered match.
    private static func indicesIntoOriginal(
        lowercased: String,
        original: String,
        range: Range<String.Index>
    ) -> Set<Int> {
        guard lowercased.count == original.count else { return [] }
        let lowerCharacters = Array(lowercased)
        let originalCharacters = Array(original)
        let startOffset = lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)
        let endOffset = lowercased.distance(from: lowercased.startIndex, to: range.upperBound)
        guard startOffset >= 0, endOffset <= lowerCharacters.count, startOffset < endOffset else {
            return []
        }
        // Walk and confirm the mapping holds character-for-character. If a non-ASCII
        // fold mismatches at any position, bail.
        for offset in startOffset..<endOffset {
            if String(lowerCharacters[offset]) != String(originalCharacters[offset]).lowercased() {
                return []
            }
        }
        return Set(startOffset..<endOffset)
    }
}

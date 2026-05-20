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
/// 5. Filename fuzzy-matches the query — the query characters appear in order with
///    gaps, so `foobar` matches `foo-bar.swift`. Word-boundary and consecutive-run
///    bonuses (fzy-style scoring) keep the best matches on top.
/// 6. Full relative path fuzzy-matches the query.
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
    private static let tierFuzzyBasename = 800_000
    private static let tierFuzzyPath = 600_000
    /// Shorter strings beat longer ones in the same tier. Clamped so a single character
    /// difference matters but pathological 10k-char paths don't underflow.
    private static let lengthPenaltyCap = 10_000
    /// Fuzzy scores are clamped into this half-band so they differentiate within their
    /// tier without bleeding into a neighboring tier (tiers are 200k apart).
    private static let fuzzyScoreBand = 90_000
    /// Skip fuzzy matching for haystacks longer than this. The O(query × haystack) DP
    /// stays cheap at file-name / relative-path scale; this guards against pathological
    /// inputs without affecting realistic paths.
    private static let fuzzyBasenameMaxLength = 128
    private static let fuzzyPathMaxLength = 256

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
        let needleChars = Array(needle)

        var matches: [Match] = []
        matches.reserveCapacity(min(candidates.count, 1024))

        for candidate in candidates {
            if shouldCancel() { break }
            guard let match = Self.scoreCandidate(
                candidate,
                needle: needle,
                needleChars: needleChars
            ) else {
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

    private static func scoreCandidate(
        _ candidate: Candidate,
        needle: String,
        needleChars: [Character]
    ) -> Match? {
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
        if let fuzzy = Self.fuzzyMatch(
            needle: needleChars,
            haystackLower: candidate.fileNameLower,
            haystackOriginal: candidate.fileName,
            maxLength: Self.fuzzyBasenameMaxLength
        ) {
            return Match(
                id: candidate.id,
                score: Self.tierFuzzyBasename + Self.clampFuzzyScore(fuzzy.score),
                fileName: candidate.fileName,
                relativePath: candidate.relativePath,
                fileNameMatchIndices: Set(fuzzy.indices)
            )
        }
        if let fuzzy = Self.fuzzyMatch(
            needle: needleChars,
            haystackLower: candidate.relativePathLower,
            haystackOriginal: candidate.relativePath,
            maxLength: Self.fuzzyPathMaxLength
        ) {
            return Match(
                id: candidate.id,
                score: Self.tierFuzzyPath + Self.clampFuzzyScore(fuzzy.score),
                fileName: candidate.fileName,
                relativePath: candidate.relativePath,
                fileNameMatchIndices: []
            )
        }
        return nil
    }

    private static func clampFuzzyScore(_ score: Int) -> Int {
        min(Self.fuzzyScoreBand, max(-Self.fuzzyScoreBand, score))
    }

    // MARK: - Fuzzy matching

    // fzy-style scoring constants (https://github.com/jhawthorn/fzy), scaled to integers.
    private static let scoreMin = -1_000_000
    private static let scoreGapLeading = -5
    private static let scoreGapTrailing = -5
    private static let scoreGapInner = -10
    private static let scoreMatchConsecutive = 1_000
    private static let scoreMatchSlash = 900
    private static let scoreMatchWord = 800
    private static let scoreMatchCapital = 700
    private static let scoreMatchDot = 600

    /// Fuzzy-matches `needle` (already lowercased) against `haystackLower`, returning the
    /// fzy-style score and the matched character offsets into the haystack. Returns nil
    /// when `needle` is not an in-order subsequence of the haystack.
    ///
    /// A cheap O(haystack) subsequence pre-check rejects the common non-match case
    /// before any array allocation or DP work, so this stays fast even when most
    /// candidates fail.
    static func fuzzyMatch(
        needle: [Character],
        haystackLower: String,
        haystackOriginal: String,
        maxLength: Int
    ) -> (score: Int, indices: [Int])? {
        let queryLength = needle.count
        guard queryLength > 0 else { return nil }

        // Cheap subsequence pre-check on the String — no allocation for non-matches.
        var matched = 0
        var haystackLength = 0
        for ch in haystackLower {
            haystackLength += 1
            if matched < queryLength, ch == needle[matched] {
                matched += 1
            }
        }
        guard matched == queryLength else { return nil }
        guard haystackLength <= maxLength, queryLength <= haystackLength else { return nil }

        let hayLower = Array(haystackLower)
        let hayOriginal = Array(haystackOriginal)
        // Capital-boundary bonus needs the original casing; only trust it when the fold
        // preserved the character count (true for ASCII, the overwhelming common case).
        let bonusChars = hayOriginal.count == hayLower.count ? hayOriginal : hayLower

        var bonus = [Int](repeating: 0, count: haystackLength)
        for j in 0..<haystackLength {
            bonus[j] = Self.matchBonus(
                current: bonusChars[j],
                previous: j == 0 ? "/" : bonusChars[j - 1]
            )
        }

        // Flat row-major DP buffers: D = best score ending in a match at [i][j],
        // M = best score for needle[0...i] over haystack[0...j].
        let cellCount = queryLength * haystackLength
        var dpD = [Int](repeating: Self.scoreMin, count: cellCount)
        var dpM = [Int](repeating: Self.scoreMin, count: cellCount)

        for i in 0..<queryLength {
            let rowOffset = i * haystackLength
            let prevRowOffset = rowOffset - haystackLength
            let gapScore = (i == queryLength - 1) ? Self.scoreGapTrailing : Self.scoreGapInner
            var prevScore = Self.scoreMin
            for j in 0..<haystackLength {
                let cell = rowOffset + j
                if needle[i] == hayLower[j] {
                    var score = Self.scoreMin
                    if i == 0 {
                        score = (j * Self.scoreGapLeading) + bonus[j]
                    } else if j > 0 {
                        let diag = prevRowOffset + j - 1
                        score = max(
                            dpM[diag] + bonus[j],
                            dpD[diag] + Self.scoreMatchConsecutive
                        )
                    }
                    dpD[cell] = score
                    prevScore = max(score, prevScore + gapScore)
                    dpM[cell] = prevScore
                } else {
                    dpD[cell] = Self.scoreMin
                    prevScore = prevScore + gapScore
                    dpM[cell] = prevScore
                }
            }
        }

        let finalScore = dpM[cellCount - 1]

        // Reconstruct matched positions by walking the DP backwards (fzy `match_positions`).
        var indices = [Int](repeating: 0, count: queryLength)
        var matchRequired = false
        var j = haystackLength - 1
        var i = queryLength - 1
        while i >= 0 {
            let rowOffset = i * haystackLength
            while j >= 0 {
                let cell = rowOffset + j
                if dpD[cell] != Self.scoreMin,
                   matchRequired || dpD[cell] == dpM[cell] {
                    if i > 0, j > 0 {
                        let diag = (i - 1) * haystackLength + j - 1
                        matchRequired = dpM[cell] == dpD[diag] + Self.scoreMatchConsecutive
                    } else {
                        matchRequired = false
                    }
                    indices[i] = j
                    j -= 1
                    break
                }
                j -= 1
            }
            i -= 1
        }

        return (finalScore, indices)
    }

    private static func matchBonus(current: Character, previous: Character) -> Int {
        switch previous {
        case "/":
            return Self.scoreMatchSlash
        case "-", "_", " ":
            return Self.scoreMatchWord
        case ".":
            return Self.scoreMatchDot
        default:
            if current.isUppercase, previous.isLowercase {
                return Self.scoreMatchCapital
            }
            return 0
        }
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

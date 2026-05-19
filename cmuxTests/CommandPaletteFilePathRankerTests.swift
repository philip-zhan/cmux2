import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class CommandPaletteFilePathRankerTests: XCTestCase {
    private func candidate(_ path: String) -> CommandPaletteFilePathRanker.Candidate {
        let fileName = (path as NSString).lastPathComponent
        return CommandPaletteFilePathRanker.Candidate(
            id: "file:" + path,
            fileName: fileName,
            relativePath: path,
            fileNameLower: fileName.lowercased(),
            relativePathLower: path.lowercased()
        )
    }

    func testBasenameStartsWithBeatsBasenameContains() {
        let candidates = [
            candidate("views/cell/LargeButtonContainer.swift"),
            candidate("views/cell/ButtonRow.swift"),
        ]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "Button",
            candidates: candidates,
            limit: 10
        )
        XCTAssertEqual(matches.map(\.id), [
            "file:views/cell/ButtonRow.swift",
            "file:views/cell/LargeButtonContainer.swift",
        ])
    }

    func testBasenameContainsBeatsPathContains() {
        let candidates = [
            candidate("views/cell/RowView.swift"),
            candidate("cell/Other.swift"),
        ]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "cell",
            candidates: candidates,
            limit: 10
        )
        XCTAssertEqual(matches.map(\.id).first, "file:cell/Other.swift")
        XCTAssertTrue(matches.map(\.id).contains("file:views/cell/RowView.swift"))
    }

    func testExactBasenameMatchWinsAll() {
        let candidates = [
            candidate("a/ContentView.swift"),
            candidate("b/View.swift"),
            candidate("c/ViewWrapper.swift"),
        ]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "View.swift",
            candidates: candidates,
            limit: 10
        )
        XCTAssertEqual(matches.first?.id, "file:b/View.swift")
    }

    func testShorterFilenameOutranksLongerInSameTier() {
        let candidates = [
            candidate("a/ContentViewContainer.swift"),
            candidate("a/ContentView.swift"),
        ]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "Content",
            candidates: candidates,
            limit: 10
        )
        XCTAssertEqual(matches.map(\.id), [
            "file:a/ContentView.swift",
            "file:a/ContentViewContainer.swift",
        ])
    }

    func testCaseInsensitiveMatching() {
        let candidates = [candidate("App/ContentView.swift")]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "contentview",
            candidates: candidates,
            limit: 10
        )
        XCTAssertEqual(matches.count, 1)
    }

    func testResultLimitTrimsLowerScores() {
        let candidates = (0..<100).map { candidate("dir/file-\($0).swift") }
        let matches = CommandPaletteFilePathRanker.rank(
            query: "file",
            candidates: candidates,
            limit: 5
        )
        XCTAssertEqual(matches.count, 5)
    }

    func testEmptyQueryReturnsCandidatesUpToLimit() {
        let candidates = (0..<10).map { candidate("dir/file-\($0).swift") }
        let matches = CommandPaletteFilePathRanker.rank(
            query: "",
            candidates: candidates,
            limit: 3
        )
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches.first?.id, "file:dir/file-0.swift")
    }

    func testMatchIndicesPointIntoBasename() {
        let candidates = [candidate("a/ContentView.swift")]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "View",
            candidates: candidates,
            limit: 10
        )
        XCTAssertEqual(matches.count, 1)
        // "ContentView.swift" -> indices 7..<11 cover "View".
        XCTAssertEqual(matches.first?.fileNameMatchIndices, Set(7..<11))
    }

    func testPathContainsLeavesFileNameIndicesEmpty() {
        let candidates = [candidate("views/cell/Row.swift")]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "cell",
            candidates: candidates,
            limit: 10
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches.first?.fileNameMatchIndices.isEmpty == true)
    }

    func testNonMatchingQueryReturnsNothing() {
        let candidates = [
            candidate("views/cell/Row.swift"),
            candidate("a/Foo.swift"),
        ]
        let matches = CommandPaletteFilePathRanker.rank(
            query: "zzz-not-present",
            candidates: candidates,
            limit: 10
        )
        XCTAssertTrue(matches.isEmpty)
    }
}

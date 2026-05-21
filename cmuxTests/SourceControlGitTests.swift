import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Behavior-level coverage for the Source Control git plumbing. Porcelain
/// parsing is exercised directly with synthetic `-z` payloads; `status` runs
/// against a throwaway repo under a temp directory.
final class SourceControlGitTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-source-control-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Porcelain parsing

    func testParsesUnstagedModifiedFile() {
        let raw = " M src/app.swift\u{0}"
        let changes = SourceControlGit.parsePorcelainZ(raw, repoRoot: "/repo")
        XCTAssertEqual(changes.count, 1)
        let change = changes[0]
        XCTAssertEqual(change.relativePath, "src/app.swift")
        XCTAssertEqual(change.displayName, "app.swift")
        XCTAssertEqual(change.directoryPath, "src")
        XCTAssertEqual(change.kind, .modified)
        XCTAssertFalse(change.isStaged)
        XCTAssertEqual(change.absolutePath, "/repo/src/app.swift")
    }

    func testParsesUntrackedFile() {
        let raw = "?? notes.txt\u{0}"
        let changes = SourceControlGit.parsePorcelainZ(raw, repoRoot: "/repo")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].kind, .untracked)
        XCTAssertFalse(changes[0].isStaged)
    }

    func testParsesStagedAndUnstagedVariantsOfSameFile() {
        // Staged modification plus a further unstaged edit: `MM <path>`.
        let raw = "MM main.swift\u{0}"
        let changes = SourceControlGit.parsePorcelainZ(raw, repoRoot: "/repo")
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.contains { $0.isStaged && $0.kind == .modified })
        XCTAssertTrue(changes.contains { !$0.isStaged && $0.kind == .modified })
        // The staged and unstaged rows must have distinct identities.
        XCTAssertNotEqual(changes[0].id, changes[1].id)
    }

    func testParsesRenameWithOriginalPath() {
        // A staged rename: `R  <new>\0<old>\0`.
        let raw = "R  lib/new.swift\u{0}lib/old.swift\u{0}"
        let changes = SourceControlGit.parsePorcelainZ(raw, repoRoot: "/repo")
        XCTAssertEqual(changes.count, 1)
        let change = changes[0]
        XCTAssertEqual(change.kind, .renamed)
        XCTAssertTrue(change.isStaged)
        XCTAssertEqual(change.relativePath, "lib/new.swift")
        XCTAssertEqual(change.originalPath, "lib/old.swift")
    }

    func testParsesMultipleRecords() {
        let raw = " M a.txt\u{0}?? b.txt\u{0}D  c.txt\u{0}"
        let changes = SourceControlGit.parsePorcelainZ(raw, repoRoot: "/repo")
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(Set(changes.map(\.relativePath)), ["a.txt", "b.txt", "c.txt"])
    }

    // MARK: - status against a real repo

    func testStatusReportsModifiedStagedAndUntracked() throws {
        try initRepo()
        try write("tracked.txt", "one\n")
        try runGit(["add", "tracked.txt"])
        try runGit(["commit", "-m", "init"])

        // Unstaged modification.
        try write("tracked.txt", "one\ntwo\n")
        // Staged new file.
        try write("staged.txt", "staged\n")
        try runGit(["add", "staged.txt"])
        // Untracked file.
        try write("fresh.txt", "fresh\n")

        let result = SourceControlGit.status(directory: tempDir.path)
        XCTAssertTrue(result.isRepository)
        XCTAssertEqual(result.branchName, "main")

        XCTAssertTrue(result.changes.contains {
            $0.relativePath == "tracked.txt" && !$0.isStaged && $0.kind == .modified
        })
        XCTAssertTrue(result.changes.contains {
            $0.relativePath == "staged.txt" && $0.isStaged && $0.kind == .added
        })
        XCTAssertTrue(result.changes.contains {
            $0.relativePath == "fresh.txt" && $0.kind == .untracked
        })
    }

    func testStatusReportsNotRepositoryOutsideRepo() {
        let result = SourceControlGit.status(directory: tempDir.path)
        XCTAssertFalse(result.isRepository)
        XCTAssertNil(result.repoRoot)
        XCTAssertTrue(result.changes.isEmpty)
    }

    // MARK: - discard

    func testDiscardRestoresTrackedFile() throws {
        try initRepo()
        try write("doc.txt", "original\n")
        try runGit(["add", "doc.txt"])
        try runGit(["commit", "-m", "init"])
        try write("doc.txt", "tampered\n")

        let repoRoot = try XCTUnwrap(SourceControlGit.status(directory: tempDir.path).repoRoot)
        SourceControlGit.discard(
            repoRoot: repoRoot,
            kind: .modified,
            relativePath: "doc.txt",
            originalPath: nil,
            absolutePath: tempDir.appendingPathComponent("doc.txt").path
        )

        let restored = try String(contentsOf: tempDir.appendingPathComponent("doc.txt"), encoding: .utf8)
        XCTAssertEqual(restored, "original\n")
    }

    func testDiscardDeletesUntrackedFile() throws {
        try initRepo()
        let url = tempDir.appendingPathComponent("junk.txt")
        try write("junk.txt", "junk\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        SourceControlGit.discard(
            repoRoot: tempDir.path,
            kind: .untracked,
            relativePath: "junk.txt",
            originalPath: nil,
            absolutePath: url.path
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - helpers

    private func initRepo() throws {
        try runGit(["init", "-q", "-b", "main"])
        try runGit(["config", "user.email", "test@example.com"])
        try runGit(["config", "user.name", "Test"])
        try runGit(["config", "commit.gpgsign", "false"])
    }

    private func write(_ name: String, _ contents: String) throws {
        try contents.write(
            to: tempDir.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    @discardableResult
    private func runGit(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = tempDir
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "<no stderr>"
            throw NSError(
                domain: "SourceControlGitTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(message)"]
            )
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

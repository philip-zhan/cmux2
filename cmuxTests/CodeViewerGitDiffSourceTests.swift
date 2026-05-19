import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Behavior-level coverage for the working-copy diff source. Builds a
/// throwaway git repo under a temp directory so the test is hermetic.
final class CodeViewerGitDiffSourceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-codeviewer-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReturnsNilOutsideGitRepo() async {
        let path = tempDir.appendingPathComponent("untracked.txt")
        try? "hello".write(to: path, atomically: true, encoding: .utf8)
        let diff = await CodeViewerGitDiffSource.load(filePath: path.path)
        XCTAssertNil(diff)
    }

    func testReportsOriginalAndModifiedAfterEdit() async throws {
        try initRepo()
        let path = tempDir.appendingPathComponent("greeting.txt")
        try "hello\n".write(to: path, atomically: true, encoding: .utf8)
        try runGit(["add", "greeting.txt"])
        try runGit(["commit", "-m", "init"])

        try "hello\nworld\n".write(to: path, atomically: true, encoding: .utf8)

        let loaded = await CodeViewerGitDiffSource.load(filePath: path.path)
        let diff = try XCTUnwrap(loaded)
        XCTAssertEqual(diff.original, "hello\n")
        XCTAssertEqual(diff.modified, "hello\nworld\n")
        XCTAssertNotEqual(diff.original, diff.modified)
    }

    func testReportsEmptyOriginalForUntrackedFileInsideRepo() async throws {
        try initRepo()
        let path = tempDir.appendingPathComponent("brand-new.txt")
        try "fresh\n".write(to: path, atomically: true, encoding: .utf8)
        // No commit yet — file is not in HEAD.
        let loaded = await CodeViewerGitDiffSource.load(filePath: path.path)
        let diff = try XCTUnwrap(loaded)
        XCTAssertEqual(diff.original, "")
        XCTAssertEqual(diff.modified, "fresh\n")
    }

    // MARK: helpers

    private func initRepo() throws {
        try runGit(["init", "-q", "-b", "main"])
        try runGit(["config", "user.email", "test@example.com"])
        try runGit(["config", "user.name", "Test"])
        try runGit(["config", "commit.gpgsign", "false"])
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
                domain: "CodeViewerGitDiffSourceTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(message)"]
            )
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

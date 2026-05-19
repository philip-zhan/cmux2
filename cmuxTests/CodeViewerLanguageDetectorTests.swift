import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class CodeViewerLanguageDetectorTests: XCTestCase {
    func testExtensionMapsToLanguage() {
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.swift"), "swift")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.tsx"), "tsx")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.py"), "python")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.rs"), "rust")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.json"), "json")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.md"), "markdown")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.yaml"), "yaml")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.go"), "go")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/x.toml"), "toml")
    }

    func testCaseInsensitiveExtension() {
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/tmp/Foo.SWIFT"), "swift")
    }

    func testFilenameSpecialCases() {
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/Dockerfile"), "shell")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/Makefile"), "shell")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/CMakeLists.txt"), "cpp")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/BUILD.bazel"), "python")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/Gemfile"), "ruby")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/package.json"), "json")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/Cargo.lock"), "toml")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/work/go.mod"), "go")
    }

    func testShebangFallbackWhenExtensionIsMissing() {
        let python = Data("#!/usr/bin/env python3\nprint('hi')\n".utf8)
        XCTAssertEqual(
            CodeViewerLanguageDetector.languageId(forPath: "/tmp/foo", sampleBytes: python),
            "python"
        )

        let node = Data("#!/usr/bin/env node\nconsole.log(1)\n".utf8)
        XCTAssertEqual(
            CodeViewerLanguageDetector.languageId(forPath: "/tmp/foo", sampleBytes: node),
            "javascript"
        )

        let bash = Data("#!/bin/bash\necho hi\n".utf8)
        XCTAssertEqual(
            CodeViewerLanguageDetector.languageId(forPath: "/tmp/foo", sampleBytes: bash),
            "shell"
        )
    }

    func testExtensionWinsOverShebang() {
        // .py extension on a file with a node shebang — extension is the
        // stronger signal, so the detector should still report python.
        let nodeShebang = Data("#!/usr/bin/env node\n".utf8)
        XCTAssertEqual(
            CodeViewerLanguageDetector.languageId(forPath: "/tmp/foo.py", sampleBytes: nodeShebang),
            "python"
        )
    }

    func testUnknownFallsBackToPlain() {
        XCTAssertEqual(
            CodeViewerLanguageDetector.languageId(forPath: "/tmp/some.xyzqq", sampleBytes: nil),
            "plain"
        )
        XCTAssertEqual(
            CodeViewerLanguageDetector.languageId(forPath: "/tmp/somefilewithoutext"),
            "plain"
        )
    }

    func testDotfileFallsBackToShellWhenAppropriate() {
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/home/u/.zshrc"), "shell")
        XCTAssertEqual(CodeViewerLanguageDetector.languageId(forPath: "/home/u/.bash_profile"), "shell")
    }
}

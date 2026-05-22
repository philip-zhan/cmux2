import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class CodePreviewEngineSettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        let suite = "cmux.codePreviewEngine.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaultsToAuto() {
        XCTAssertEqual(CodePreviewEngineSettings.current(defaults: defaults), .auto)
    }

    func testReadsExplicitEngineFromDefaults() {
        defaults.set(CodePreviewEngine.codeMirror.rawValue, forKey: CodePreviewEngineSettings.engineKey)
        XCTAssertEqual(CodePreviewEngineSettings.current(defaults: defaults), .codeMirror)
    }

    func testNativeTextEngineNeverPicksCodeMirror() {
        defaults.set(CodePreviewEngine.nativeText.rawValue, forKey: CodePreviewEngineSettings.engineKey)
        XCTAssertFalse(CodePreviewEngineSettings.shouldUseCodeMirror(forPath: "/tmp/foo.swift", defaults: defaults))
        XCTAssertFalse(CodePreviewEngineSettings.shouldUseCodeMirror(forPath: "/tmp/foo.bin", defaults: defaults))
    }

    func testCodeMirrorEngineAlwaysPicksCodeMirror() {
        defaults.set(CodePreviewEngine.codeMirror.rawValue, forKey: CodePreviewEngineSettings.engineKey)
        XCTAssertTrue(CodePreviewEngineSettings.shouldUseCodeMirror(forPath: "/tmp/foo.swift", defaults: defaults))
        XCTAssertTrue(CodePreviewEngineSettings.shouldUseCodeMirror(forPath: "/tmp/unknown.xyzqq", defaults: defaults))
    }

    func testAutoEngineUsesDetectorAndSkipsPlain() {
        defaults.set(CodePreviewEngine.auto.rawValue, forKey: CodePreviewEngineSettings.engineKey)
        XCTAssertTrue(CodePreviewEngineSettings.shouldUseCodeMirror(forPath: "/tmp/foo.swift", defaults: defaults))
        XCTAssertTrue(CodePreviewEngineSettings.shouldUseCodeMirror(forPath: "/tmp/foo.py", defaults: defaults))
        XCTAssertFalse(CodePreviewEngineSettings.shouldUseCodeMirror(forPath: "/tmp/unknown.xyzqq", defaults: defaults))
    }
}

import Foundation

/// Which engine the file preview panel should use for code-like files.
///
/// Stage 6 of the code viewer rollout ships the flag and a Settings UI for
/// it; the actual `FilePreviewPanel` integration (routing into either the
/// existing `NSTextView` path or the new `CodeWebRenderer`) lands in a
/// follow-up PR so this branch stays a focused spike.
enum CodePreviewEngine: String, CaseIterable, Identifiable {
    /// Today's behavior — `NSTextView`-backed `FilePreviewTextEditor`.
    case nativeText = "nativeText"
    /// Bundled CodeMirror 6 in a `WKWebView` (`CodeWebRenderer`).
    case codeMirror = "codeMirror"
    /// Default-on for languages the detector recognizes, fall back to
    /// `nativeText` otherwise (or for very large files).
    case auto = "auto"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nativeText:
            return String(
                localized: "codePreview.engine.nativeText",
                defaultValue: "Native text editor"
            )
        case .codeMirror:
            return String(
                localized: "codePreview.engine.codeMirror",
                defaultValue: "CodeMirror (beta)"
            )
        case .auto:
            return String(
                localized: "codePreview.engine.auto",
                defaultValue: "Automatic"
            )
        }
    }
}

enum CodePreviewEngineSettings {
    static let engineKey = "codePreviewEngine"
    // Default to `.auto`: CodeMirror picks up any file the language detector
    // recognizes; plain/large files fall back to the NSTextView engine.
    // Set `codePreviewEngine = nativeText` in defaults to revert globally.
    static let defaultEngine: CodePreviewEngine = .auto

    static func current(defaults: UserDefaults = .standard) -> CodePreviewEngine {
        guard let raw = defaults.string(forKey: engineKey),
              let engine = CodePreviewEngine(rawValue: raw) else {
            return defaultEngine
        }
        return engine
    }

    /// Convenience for the eventual `FilePreviewPanel` integration: returns
    /// `true` when the caller should mount the new `CodeWebRenderer` for
    /// the given file path. Stage 6 routing PR will consume this; for now
    /// it's exercised by tests so the policy is locked in.
    static func shouldUseCodeMirror(
        forPath path: String,
        fileSize: Int? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        switch current(defaults: defaults) {
        case .nativeText:
            return false
        case .codeMirror:
            return true
        case .auto:
            if let fileSize, fileSize > maxAutoFileSizeBytes {
                return false
            }
            let lang = CodeViewerLanguageDetector.languageId(forPath: path)
            return lang != "plain"
        }
    }

    /// Auto-mode bails to the native path above this size. Big-file guard
    /// inside CodeMirror itself (Stage 2 follow-up) can ratchet this down
    /// when we add the read-only large-file mode.
    static let maxAutoFileSizeBytes = 5 * 1024 * 1024
}

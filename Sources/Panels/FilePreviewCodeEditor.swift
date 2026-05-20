import AppKit
import SwiftUI
import WebKit

/// SwiftUI wrapper that drives `CodeWebRenderer` from a `FilePreviewPanel`.
///
/// Stage 6 of the code viewer rollout: when `CodePreviewEngineSettings`
/// routes a text-mode panel to CodeMirror, `FilePreviewPanelView` mounts this
/// view instead of `FilePreviewTextEditor`. The on-disk snapshot
/// (`panel.originalTextContent`) drives the renderer's `content:` prop so
/// per-keystroke edits don't churn the WebKit payload; the live in-memory
/// buffer lives in the JS editor and is reported back through
/// `onContentChanged`.
struct FilePreviewCodeEditor: View {
    @ObservedObject var panel: FilePreviewPanel
    let isVisibleInUI: Bool
    let themeBackgroundColor: NSColor
    let themeForegroundColor: NSColor
    let drawsBackground: Bool

    var body: some View {
        CodeWebRenderer(
            content: panel.originalTextContent,
            languageId: detectedLanguageId,
            theme: theme,
            fontSize: defaultFontSize,
            isReadOnly: false,
            diffOriginal: nil,
            diffModified: nil,
            backgroundColor: rendererBackgroundColor,
            panelId: panel.id,
            workspaceId: panel.workspaceId,
            filePath: panel.filePath,
            session: panel.nativeViewSessions.code,
            onRequestPanelFocus: handlePointerFocus,
            onSaveRequested: handleSaveRequested,
            onContentChanged: handleContentChanged,
            onFontSizeChanged: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: rendererBackgroundColor))
        .opacity(isVisibleInUI ? 1 : 0)
        .allowsHitTesting(isVisibleInUI)
        .accessibilityHidden(!isVisibleInUI)
        .background(
            FilePreviewCodeEditorFocusBridge(panel: panel)
                .allowsHitTesting(false)
        )
    }

    private var detectedLanguageId: String {
        CodeViewerLanguageDetector.languageId(forPath: panel.filePath)
    }

    private var rendererBackgroundColor: NSColor {
        drawsBackground ? themeBackgroundColor : .clear
    }

    private var theme: CodeWebTheme {
        CodeWebTheme.resolve(
            backgroundColor: themeBackgroundColor,
            foregroundColor: themeForegroundColor
        )
    }

    private var defaultFontSize: Int { 13 }

    private func handlePointerFocus() {
        // Pointer-down inside the web view should treat the file preview the
        // same way a click on the NSTextView does: announce focus intent so
        // the panel framework can route navigation.
        panel.noteFilePreviewFocusIntent(.textEditor)
    }

    private func handleContentChanged(_ next: String) {
        panel.updateTextContent(next)
    }

    private func handleSaveRequested() {
        // The Swift-side save chord fires immediately when the user presses
        // the configured shortcut, but the JS bridge debounces
        // `contentChanged` by 120ms. Pull the live document from the editor
        // before saving so we never persist a stale snapshot.
        let session = panel.nativeViewSessions.code
        Task { @MainActor in
            if let latest = await session.currentDocument() {
                panel.updateTextContent(latest)
            }
            _ = panel.saveTextContent()
        }
    }
}

/// AppKit shim that registers the WKWebView underneath
/// `FilePreviewCodeEditor` with the panel's focus coordinator so
/// `panel.focus()` / restoreFocusIntent works the same way it does for the
/// NSTextView engine.
private struct FilePreviewCodeEditorFocusBridge: NSViewRepresentable {
    let panel: FilePreviewPanel

    func makeNSView(context: Context) -> FilePreviewCodeEditorFocusBridgeView {
        let view = FilePreviewCodeEditorFocusBridgeView()
        view.panel = panel
        return view
    }

    func updateNSView(_ nsView: FilePreviewCodeEditorFocusBridgeView, context: Context) {
        nsView.panel = panel
        nsView.registerIfNeeded()
    }
}

private final class FilePreviewCodeEditorFocusBridgeView: NSView {
    weak var panel: FilePreviewPanel?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerIfNeeded()
    }

    func registerIfNeeded() {
        guard let panel else { return }
        guard let webView = findCodeWebView() else { return }
        panel.attachPreviewFocus(
            root: webView,
            primaryResponder: webView,
            intent: .textEditor
        )
    }

    /// Walks the sibling tree to find the CodeWebView (it's mounted by the
    /// neighboring `CodeWebRenderer` representable, not as a subview of this
    /// bridge view). We start from the immediate superview and recurse.
    private func findCodeWebView() -> CodeWebView? {
        guard let superview = superview else { return nil }
        return Self.search(in: superview)
    }

    private static func search(in view: NSView) -> CodeWebView? {
        if let codeWebView = view as? CodeWebView {
            return codeWebView
        }
        for subview in view.subviews {
            if let found = search(in: subview) {
                return found
            }
        }
        return nil
    }
}

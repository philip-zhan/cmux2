import AppKit
import SwiftUI

/// Read-only side-by-side diff view for a `FilePreviewPanel` opened with
/// `diffAgainstHead`. Drives the same `CodeWebRenderer` as the editable code
/// editor, but feeds it the HEAD and working-tree blobs so the bundled
/// CodeMirror `MergeView` renders the diff.
struct FilePreviewDiffEditor<PanelModel>: View
where PanelModel: ObservableObject & CodeMirrorEditingPanel {
    @ObservedObject var panel: PanelModel
    let diffOriginal: String
    let diffModified: String
    let isVisibleInUI: Bool
    let themeBackgroundColor: NSColor
    let themeForegroundColor: NSColor
    let drawsBackground: Bool

    var body: some View {
        CodeWebRenderer(
            content: diffModified,
            languageId: CodeViewerLanguageDetector.languageId(forPath: panel.filePath),
            theme: theme,
            fontSize: 13,
            isReadOnly: true,
            diffOriginal: diffOriginal,
            diffModified: diffModified,
            backgroundColor: rendererBackgroundColor,
            panelId: panel.id,
            workspaceId: panel.workspaceId,
            filePath: panel.filePath,
            session: panel.codeRendererSession,
            onRequestPanelFocus: { panel.noteCodeEditorPointerFocus() },
            onSaveRequested: {},
            onContentChanged: { _ in },
            onFontSizeChanged: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: rendererBackgroundColor))
        .opacity(isVisibleInUI ? 1 : 0)
        .allowsHitTesting(isVisibleInUI)
        .accessibilityHidden(!isVisibleInUI)
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
}

import AppKit
import Foundation

/// Routes the command palette `.files` open action to the right surface (built-in file
/// preview, external editor, or Finder-reveal). The step-3 implementation logs the
/// chosen file in DEBUG and falls back to Launch Services so the wiring can be
/// exercised end-to-end; step 4 swaps this for FilePreviewPanel routing.
@MainActor
final class CommandPaletteFileOpenRouter {
    static let shared = CommandPaletteFileOpenRouter()

    func open(absolutePath: String) {
        let url = URL(fileURLWithPath: absolutePath)
#if DEBUG
        cmuxDebugLog("palette.file.open path=\(absolutePath)")
#endif
        NSWorkspace.shared.open(url)
    }
}

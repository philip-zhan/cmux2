import Foundation

@MainActor
final class FilePreviewNativeViewSessions {
    let pdf = FilePreviewPDFSession()
    let image = FilePreviewImageSession()
    let media = FilePreviewMediaSession()
    let quickLook = FilePreviewQuickLookSession()
    let code = CodeRendererSession()

    deinit {
        // AppKit teardown is performed explicitly by closeAll() on the main actor.
    }

    func closeInactive(except mode: FilePreviewMode) {
        switch mode {
        case .text:
            // Code session stays alive in text mode — it backs the optional
            // CodeMirror text engine. The other native sessions are torn down.
            pdf.close()
            image.close()
            media.close()
            quickLook.close()
        case .pdf:
            image.close()
            media.close()
            quickLook.close()
            code.close()
        case .image:
            pdf.close()
            media.close()
            quickLook.close()
            code.close()
        case .media:
            pdf.close()
            image.close()
            quickLook.close()
            code.close()
        case .quickLook:
            pdf.close()
            image.close()
            media.close()
            code.close()
        }
    }

    func closeAll() {
        pdf.close()
        image.close()
        media.close()
        quickLook.close()
        code.close()
    }
}

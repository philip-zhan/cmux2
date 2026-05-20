import Foundation

/// Loads the bundled CodeMirror 6 web viewer assets from
/// `Resources/code-viewer/`. The shell HTML carries a `{{codeViewerJS}}`
/// placeholder that is replaced with the bundled `code-viewer.js` at
/// runtime; this mirrors how `MarkdownViewerAssets` inlines its bundle.
@MainActor
final class CodeViewerAssets {
    static let shared = CodeViewerAssets()

    private let codeViewerJS: String
    private let shellTemplate: String

    private init() {
        codeViewerJS = CodeViewerAssets.loadAsset(name: "code-viewer", ext: "js")
        shellTemplate = CodeViewerAssets.loadAsset(name: "shell", ext: "html")
    }

    func shellHTML() -> String {
        shellTemplate.replacingOccurrences(of: "{{codeViewerJS}}", with: codeViewerJS)
    }

    private static func loadAsset(name: String, ext: String) -> String {
        let bundle = Bundle.main
        let compressedCandidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "\(ext).deflate", subdirectory: "code-viewer"),
            bundle.url(forResource: name, withExtension: "\(ext).deflate")
        ]
        for case let url? in compressedCandidates {
            guard let s = loadDeflatedTextAsset(url: url) else {
#if DEBUG
                NSLog("CodeViewerAssets: invalid compressed asset \(url.path)")
#endif
                preconditionFailure("Invalid compressed code viewer asset \(url.lastPathComponent)")
            }
            return s
        }

        let candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: ext, subdirectory: "code-viewer"),
            bundle.url(forResource: name, withExtension: ext)
        ]
        for case let url? in candidates {
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                return s
            }
        }
#if DEBUG
        NSLog("CodeViewerAssets: missing bundled asset \(name).\(ext)")
#endif
        preconditionFailure("Missing bundled code viewer asset \(name).\(ext)")
    }

    private static func loadDeflatedTextAsset(url: URL) -> String? {
        guard let compressed = try? Data(contentsOf: url),
              let decompressed = try? (compressed as NSData).decompressed(using: .zlib) as Data else {
            return nil
        }
        return String(data: decompressed, encoding: .utf8)
    }
}

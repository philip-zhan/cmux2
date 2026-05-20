import Foundation

/// Maps a file path (and, where available, its first bytes) to a CodeMirror
/// language id that the bundled `code-viewer.js` understands.
///
/// Order of preference:
/// 1. Filename match (`Dockerfile`, `Makefile`, `CMakeLists.txt`, …)
/// 2. File extension
/// 3. Shebang sniff
/// 4. `"plain"` fallback (no syntax highlighting)
enum CodeViewerLanguageDetector {
    static func languageId(forPath path: String, sampleBytes: Data? = nil) -> String {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if let byName = languageForFilename(filename) {
            return byName
        }
        if !ext.isEmpty, let byExt = languageForExtension(ext) {
            return byExt
        }
        if let bytes = sampleBytes, let viaShebang = languageForShebang(bytes) {
            return viaShebang
        }
        return "plain"
    }

    private static func languageForFilename(_ filename: String) -> String? {
        switch filename {
        case "Dockerfile", "Containerfile":              return "shell"
        case "Makefile", "GNUmakefile", "BSDmakefile":   return "shell"
        case "CMakeLists.txt":                           return "cpp"
        case "BUCK", "BUILD", "BUILD.bazel", "WORKSPACE": return "python"
        case "Gemfile", "Rakefile":                      return "ruby"
        case "Podfile":                                  return "ruby"
        case "Brewfile":                                 return "ruby"
        case "Cargo.lock":                               return "toml"
        case "go.mod", "go.sum":                         return "go"
        case "package.json", "tsconfig.json":            return "json"
        default:
            // Common ".rc" config dotfiles — best-effort shell highlighting.
            if filename.hasPrefix(".") && (filename.hasSuffix("rc") || filename.hasSuffix("_profile")) {
                return "shell"
            }
            return nil
        }
    }

    private static func languageForExtension(_ ext: String) -> String? {
        switch ext {
        case "ts":               return "typescript"
        case "tsx":              return "tsx"
        case "js", "mjs", "cjs": return "javascript"
        case "jsx":              return "jsx"
        case "py", "pyi":        return "python"
        case "rs":               return "rust"
        case "json", "jsonc":    return "json"
        case "md", "markdown", "mdx": return "markdown"
        case "html", "htm":      return "html"
        case "css", "scss", "sass", "less": return "css"
        case "sql":              return "sql"
        case "yml", "yaml":      return "yaml"
        case "xml", "plist", "storyboard", "xib", "svg": return "xml"
        case "c", "h":           return "cpp"
        case "cc", "cpp", "cxx", "hpp", "hh", "hxx", "mm", "m": return "cpp"
        case "go":               return "go"
        case "java":             return "java"
        case "kt", "kts":        return "java"  // approximate
        case "php":              return "php"
        case "swift":            return "swift"
        case "sh", "bash", "zsh", "fish", "ksh": return "shell"
        case "toml":             return "toml"
        case "rb":               return "ruby"
        case "lua":              return "lua"
        case "txt", "log":       return "plain"
        default:                 return nil
        }
    }

    private static func languageForShebang(_ data: Data) -> String? {
        let prefix = data.prefix(256)
        guard let header = String(data: prefix, encoding: .utf8) else { return nil }
        guard header.hasPrefix("#!") else { return nil }
        let firstLine = header.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? header
        let lower = firstLine.lowercased()
        if lower.contains("python") { return "python" }
        if lower.contains("node")   { return "javascript" }
        if lower.contains("ruby")   { return "ruby" }
        if lower.contains("php")    { return "php" }
        if lower.contains("lua")    { return "lua" }
        if lower.contains("bash") || lower.contains("/sh") || lower.contains("zsh") || lower.contains("fish") {
            return "shell"
        }
        return nil
    }
}

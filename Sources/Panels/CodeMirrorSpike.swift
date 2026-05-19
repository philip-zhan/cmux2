#if DEBUG
import AppKit
import SwiftUI
import WebKit

// MARK: - Spike payload

/// Sample code/diff data the debug window seeds the editor with so we can poke
/// at language coverage, themes, scroll perf, and the merge view without
/// wiring this up to the real file preview panel yet.
enum CodeMirrorSpikeSample {
    static let swift = """
import Foundation

struct Greeting {
    let name: String

    func render() -> String {
        return \"hello, \\(name)\"
    }
}

let g = Greeting(name: \"cmux\")
print(g.render())
"""

    static let swiftModified = """
import Foundation

struct Greeting {
    let name: String
    let exclaim: Bool

    func render() -> String {
        let suffix = exclaim ? \"!\" : \"\"
        return \"hello, \\(name)\\(suffix)\"
    }
}

let g = Greeting(name: \"cmux\", exclaim: true)
print(g.render())
"""

    static let typescript = """
type User = { id: string; name: string };

export async function loadUser(id: string): Promise<User> {
  const res = await fetch(`/api/users/${id}`);
  if (!res.ok) throw new Error(`Failed: ${res.status}`);
  return (await res.json()) as User;
}
"""

    static let python = """
def fib(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

if __name__ == \"__main__\":
    print([fib(i) for i in range(10)])
"""
}

enum CodeMirrorSpikeLanguage: String, CaseIterable, Identifiable {
    case swift
    case typescript
    case python
    case rust
    case json
    case markdown

    var id: String { rawValue }

    /// Loader id understood by the JS side of the bridge — see the language
    /// import map in the shell HTML below.
    var jsLanguageId: String { rawValue }

    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .rust: return "Rust"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        }
    }
}

// MARK: - Bridge payloads

struct CodeMirrorSpikeBridgePayload: Codable {
    var content: String
    var language: String
    var isDark: Bool
    var fontSize: Int
    var diffOriginal: String?
    var diffModified: String?
}

// MARK: - HTML shell (legacy esm.sh fallback — kept for reference only)

// Production shell now ships in Resources/code-viewer/ and is loaded via
// CodeViewerAssets.shared.shellHTML(). This inline variant remains as a
// no-network development fallback if the bundle is ever missing.
private enum CodeMirrorSpikeShell {
    static let html: String = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self' 'unsafe-inline' https://esm.sh; script-src 'self' 'unsafe-inline' https://esm.sh; style-src 'self' 'unsafe-inline'; connect-src https://esm.sh">
<title>CodeMirror Spike</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
  #editor { position: absolute; inset: 0; }
  .cm-editor { height: 100%; font-size: var(--cm-font-size, 13px); }
  .cm-scroller { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  #status { position: fixed; bottom: 6px; right: 8px; opacity: 0.6; font: 10px ui-monospace, Menlo, monospace; color: #888; }
</style>
</head>
<body>
<div id="editor"></div>
<div id="status">booting…</div>
<script type="module">
const status = document.getElementById('status');
const log = (msg) => { status.textContent = msg; };

const CM_VERSION = '6';
const base = `https://esm.sh/codemirror@${CM_VERSION}`;

log('loading codemirror…');

const [
  cmState, cmView, cmCommands, cmSearch, cmLanguage,
  langJS, langPython, langRust, langJSON, langMarkdown,
  themeOneDark,
  merge,
] = await Promise.all([
  import('https://esm.sh/@codemirror/state@6'),
  import('https://esm.sh/@codemirror/view@6'),
  import('https://esm.sh/@codemirror/commands@6'),
  import('https://esm.sh/@codemirror/search@6'),
  import('https://esm.sh/@codemirror/language@6'),
  import('https://esm.sh/@codemirror/lang-javascript@6'),
  import('https://esm.sh/@codemirror/lang-python@6'),
  import('https://esm.sh/@codemirror/lang-rust@6'),
  import('https://esm.sh/@codemirror/lang-json@6'),
  import('https://esm.sh/@codemirror/lang-markdown@6'),
  import('https://esm.sh/@codemirror/theme-one-dark@6'),
  import('https://esm.sh/@codemirror/merge@6'),
]);

// Swift has no first-party CM6 grammar; legacy stream parser via @codemirror/legacy-modes
const legacySwift = await import('https://esm.sh/@codemirror/legacy-modes@6/mode/swift');
const legacyLang = await import('https://esm.sh/@codemirror/legacy-modes@6/mode/clike');

function languageExtension(id) {
  switch (id) {
    case 'typescript': return langJS.javascript({ typescript: true, jsx: true });
    case 'python':     return langPython.python();
    case 'rust':       return langRust.rust();
    case 'json':       return langJSON.json();
    case 'markdown':   return langMarkdown.markdown();
    case 'swift':      return cmLanguage.StreamLanguage.define(legacySwift.swift);
    default:           return [];
  }
}

const fontSizeCompartment = new cmState.Compartment();
const themeCompartment    = new cmState.Compartment();
const languageCompartment = new cmState.Compartment();

function baseExtensions() {
  return [
    cmView.lineNumbers(),
    cmView.highlightActiveLine(),
    cmView.highlightActiveLineGutter(),
    cmView.drawSelection(),
    cmState.EditorState.allowMultipleSelections.of(true),
    cmView.keymap.of([
      ...cmCommands.defaultKeymap,
      ...cmCommands.historyKeymap,
      ...cmSearch.searchKeymap,
    ]),
    cmCommands.history(),
    cmSearch.search({ top: true }),
    fontSizeCompartment.of(cmView.EditorView.theme({ '&': { fontSize: '13px' } })),
    themeCompartment.of([]),
    languageCompartment.of([]),
  ];
}

let editor = null;
let mergeView = null;

function mountSingle(parent, content, language, isDark) {
  if (mergeView) { mergeView.destroy(); mergeView = null; }
  if (editor) { editor.destroy(); editor = null; }

  const state = cmState.EditorState.create({
    doc: content,
    extensions: baseExtensions(),
  });
  editor = new cmView.EditorView({ parent, state });
  applyLanguage(language);
  applyTheme(isDark);
}

function mountDiff(parent, original, modified, language, isDark) {
  if (mergeView) { mergeView.destroy(); mergeView = null; }
  if (editor) { editor.destroy(); editor = null; }

  mergeView = new merge.MergeView({
    parent,
    a: { doc: original, extensions: baseExtensions() },
    b: { doc: modified, extensions: baseExtensions() },
    revertControls: 'b-to-a',
    highlightChanges: true,
    gutter: true,
  });
  applyLanguage(language);
  applyTheme(isDark);
}

function applyLanguage(id) {
  const ext = languageExtension(id);
  const reconfig = languageCompartment.reconfigure(ext);
  if (editor) editor.dispatch({ effects: reconfig });
  if (mergeView) {
    mergeView.a.dispatch({ effects: reconfig });
    mergeView.b.dispatch({ effects: reconfig });
  }
}

function applyTheme(isDark) {
  const ext = isDark ? themeOneDark.oneDark : [];
  const reconfig = themeCompartment.reconfigure(ext);
  if (editor) editor.dispatch({ effects: reconfig });
  if (mergeView) {
    mergeView.a.dispatch({ effects: reconfig });
    mergeView.b.dispatch({ effects: reconfig });
  }
  document.documentElement.style.colorScheme = isDark ? 'dark' : 'light';
}

function applyFontSize(px) {
  const ext = cmView.EditorView.theme({ '&': { fontSize: px + 'px' } });
  const reconfig = fontSizeCompartment.reconfigure(ext);
  if (editor) editor.dispatch({ effects: reconfig });
  if (mergeView) {
    mergeView.a.dispatch({ effects: reconfig });
    mergeView.b.dispatch({ effects: reconfig });
  }
}

window.__cmuxCMApply = function(payload) {
  const parent = document.getElementById('editor');
  const p = typeof payload === 'string' ? JSON.parse(payload) : payload;
  if (p.diffOriginal != null && p.diffModified != null) {
    mountDiff(parent, p.diffOriginal, p.diffModified, p.language, !!p.isDark);
  } else {
    mountSingle(parent, p.content ?? '', p.language, !!p.isDark);
  }
  applyFontSize(p.fontSize ?? 13);
  log('ready · ' + p.language + (p.diffOriginal != null ? ' · diff' : ''));
};

window.__cmuxCMGet = function() {
  if (editor) return editor.state.doc.toString();
  if (mergeView) return mergeView.b.state.doc.toString();
  return '';
};

log('ready (waiting for content)');
</script>
</body>
</html>
"""#
}

// MARK: - Web view representable

@MainActor
final class CodeMirrorSpikeWebView: WKWebView {}

struct CodeMirrorSpikeRenderer: NSViewRepresentable {
    let content: String
    let language: CodeMirrorSpikeLanguage
    let isDark: Bool
    let fontSize: Int
    let diffOriginal: String?
    let diffModified: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let webView = CodeMirrorSpikeWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        context.coordinator.webView = webView
        context.coordinator.pendingPayload = currentPayload()
        webView.loadHTMLString(
            CodeViewerAssets.shared.shellHTML(),
            baseURL: URL(string: "https://localhost/cmux-code-viewer/")
        )
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.apply(payload: currentPayload())
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
    }

    private func currentPayload() -> CodeMirrorSpikeBridgePayload {
        CodeMirrorSpikeBridgePayload(
            content: content,
            language: language.jsLanguageId,
            isDark: isDark,
            fontSize: fontSize,
            diffOriginal: diffOriginal,
            diffModified: diffModified
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isLoaded = false
        var pendingPayload: CodeMirrorSpikeBridgePayload?

        func apply(payload: CodeMirrorSpikeBridgePayload) {
            pendingPayload = payload
            guard isLoaded, let webView else { return }
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            let js = "window.__cmuxCodeApply && window.__cmuxCodeApply(\(json));"
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    NSLog("CodeMirrorSpike: apply failed: \(error)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pending = pendingPayload {
                apply(payload: pending)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("CodeMirrorSpike: nav fail \(error)")
        }
    }
}

// MARK: - Debug window

final class CodeMirrorSpikeDebugWindowController: NSWindowController, NSWindowDelegate {
    static let shared = CodeMirrorSpikeDebugWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodeMirror 6 Spike"
        window.identifier = NSUserInterfaceItemIdentifier("cmux.codemirrorSpike")
        window.center()
        window.contentView = NSHostingView(rootView: CodeMirrorSpikeDebugView())
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private struct CodeMirrorSpikeDebugView: View {
    @State private var language: CodeMirrorSpikeLanguage = .swift
    @State private var content: String = CodeMirrorSpikeSample.swift
    @State private var isDark: Bool = true
    @State private var fontSize: Double = 13
    @State private var diffEnabled: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Language", selection: $language) {
                    ForEach(CodeMirrorSpikeLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .frame(width: 220)
                .onChange(of: language) { _, newValue in
                    content = sampleFor(newValue)
                }

                Toggle("Dark", isOn: $isDark)
                Toggle("Diff view", isOn: $diffEnabled)

                HStack {
                    Text("Font")
                    Slider(value: $fontSize, in: 9...22, step: 1)
                        .frame(width: 140)
                    Text("\(Int(fontSize))pt").monospacedDigit().frame(width: 36, alignment: .trailing)
                }

                Spacer()
                Button("Reset") {
                    content = sampleFor(language)
                }
            }
            .padding(8)

            Divider()

            CodeMirrorSpikeRenderer(
                content: content,
                language: language,
                isDark: isDark,
                fontSize: Int(fontSize),
                diffOriginal: diffEnabled ? CodeMirrorSpikeSample.swift : nil,
                diffModified: diffEnabled ? CodeMirrorSpikeSample.swiftModified : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isDark ? Color(white: 0.12) : Color.white)
        }
    }

    private func sampleFor(_ lang: CodeMirrorSpikeLanguage) -> String {
        switch lang {
        case .swift:      return CodeMirrorSpikeSample.swift
        case .typescript: return CodeMirrorSpikeSample.typescript
        case .python:     return CodeMirrorSpikeSample.python
        case .rust:       return "fn main() {\n    println!(\"hello, cmux\");\n}\n"
        case .json:       return "{\n  \"hello\": \"cmux\",\n  \"count\": 1\n}\n"
        case .markdown:   return "# Hello\n\n- one\n- two\n\n```swift\nprint(\"hi\")\n```\n"
        }
    }
}
#endif

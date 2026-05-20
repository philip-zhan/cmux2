# Code viewer + diff view rollout plan

Goal: replace the `NSTextView`-based file preview (`Sources/Panels/FilePreviewTextEditor.swift`) with a `WKWebView`-hosted CodeMirror 6 editor that also handles diff. Ship in stages so each one is independently mergeable, reviewable, and revertable.

Spike branch: `spike-codemirror-file-viewer`. Proof-of-concept in `Sources/Panels/CodeMirrorSpike.swift` (Debug menu → CodeMirror 6 Spike…).

---

## Stage 0 — Bundling pipeline (foundation)

Goal: stop loading from `esm.sh`. Ship CM6 inside the app bundle.

- `web/code-viewer/` (new directory, peer of `web/`) with:
  - `package.json` pinning `@codemirror/*` versions
  - `src/index.ts` — single ESM entry that exports the editor factory and the Swift bridge
  - `src/shell.html` — template that the bundle is inlined into
  - `build.mjs` — esbuild script that produces a single `code-viewer.js`
- `scripts/build-code-viewer-assets.sh` invoked by an Xcode build phase, mirroring `scripts/compress-markdown-viewer-assets.sh`.
- Output to `Resources/code-viewer/`:
  - `shell.html`
  - `code-viewer.js` (+ `.deflate` post-build)
- `Sources/Panels/CodeViewerAssets.swift` mirroring `MarkdownViewerAssets`.
- Add `Resources/code-viewer/` folder reference to `cmux.xcodeproj`.

Exit criteria: spike runs with zero network access (verify offline).
Risk: bundle size. Audit gzipped size; target ≤ 350 KB gzipped.

## Stage 1 — Production `CodeWebRenderer` + `FilePreviewCodePanel`

Goal: a real panel that mounts CM6 the way `MarkdownPanel` mounts marked.

- `Sources/Panels/CodeWebRenderer.swift` mirroring `MarkdownWebRenderer`:
  - Coordinator with shell-load / web-content-process-crash recovery
  - Native theme bridging via existing `themeBackgroundColor` / `themeForegroundColor`
  - `applyAppearance` flipping `NSAppearance` for `prefers-color-scheme`
- `Sources/Panels/FilePreviewCodePanel.swift` conforming to the `FilePreviewTextEditingPanel` feature set so the existing panel container can host it.
- Swift → JS bridge (`cmuxCode`): `setContent`, `applyTheme`, `setReadOnly`.
- JS → Swift bridge: `ready`, `contentChanged` (debounced), `requestSave`.

Exit criteria: new file-preview mode renders code with syntax highlighting; editing/save still gated to old `NSTextView` path behind a flag.

## Stage 2 — Language detection + grammar set

- `Sources/Panels/CodeViewerLanguageDetector.swift`:
  1. Extension map
  2. Shebang sniff
  3. Filename special cases (`Dockerfile`, `Makefile`, `BUCK`, `CMakeLists.txt`)
- First-party CM6 grammars: `lang-javascript`, `lang-python`, `lang-rust`, `lang-json`, `lang-html`, `lang-css`, `lang-sql`, `lang-markdown`, `lang-yaml`, `lang-xml`, `lang-cpp`, `lang-go`, `lang-java`, `lang-php`.
- Stream-parser fallbacks via `@codemirror/legacy-modes`: Swift, Zig, Lua, Toml, Nix, Shell, Haskell, Ruby.
- Plain-text fallback for unknown / huge / binary files.
- Big-file guard above N lines or M bytes: mount with no language, banner "syntax highlighting disabled for large files."

Exit criteria: open files across the cmux repo (Swift, Zig, TS, Python, Bash, JSON, Markdown) and visually spot-check.

## Stage 3 — Editing parity

Match every behavior in `FilePreviewTextEditor.swift` and `SavingTextView`:

- Save shortcut via `KeyboardShortcutSettings.shortcut(for: .saveFilePreview)`. Intercept the chord on the Swift side; query CM6 doc on demand. Don't replicate chord state in JS.
- Dirty tracking via debounced `contentChanged`, recomputed against on-disk hash.
- Undo/redo via CM6 history.
- Find: ship CM6's `search` panel keyed off Cmd-F.
- Font zoom: pinch + Cmd-scroll → JS `setFontSize`. Clamp 8–36 pt to match current behavior.
- Selection/cursor: persist across panel re-mounts via `FilePreviewFocusCoordinator`.
- Read-only mode: pass `EditorState.readOnly.of(true)`.

Exit criteria: per the shared-behavior policy in CLAUDE.md, verify every entrypoint (file explorer double-click, command palette, terminal cmd-click) routes through the same panel factory.

## Stage 4 — Diff view

- `FilePreviewDiffPanel` wraps `CodeWebRenderer` with `original` + `modified` payload.
- JS side: `MergeView` (side-by-side) or `unifiedMergeView` (inline) per panel setting.
- Diff sources:
  - Working-copy: `git show HEAD:<path>` for original; current file content for modified.
  - Arbitrary blob: two paths or two refs.
- Affordances: hunk navigation shortcuts, inline ↔ side-by-side toggle, "ignore whitespace" (recomputed in Swift, decorations sent to CM6).
- Performance guard: above ~200 KB changed region, fall back to line-level Myers diff in Swift, send pre-marked decorations to CM6.

Exit criteria: diff matches `git diff` output line-for-line on PR-sized changes; 5 MB minified-vs-formatted file does not hang.

## Stage 5 — Theme + native polish

- CM6 theme reads palette CSS variables set by Swift (same mechanism as `MarkdownWebRenderer.applyTheme`); `HighlightStyle.define` mapped to cmux color tokens.
- Synthesize token theme from `GhosttyBackgroundTheme` so the viewer matches the active terminal theme.
- Avoid white-flash on `loadHTMLString`: hide until `didFinish`, pre-paint background, optionally warm a `WKWebView` pool per workspace.
- Accessibility pass: VoiceOver reads document; gutter line numbers don't get read on every cursor move.

Exit criteria: viewer visually consistent with markdown panel; no flash on tab switch.

## Stage 6 — Rollout, settings, kill switch

- Settings toggle: General → "Code preview engine" with options Native text / CodeMirror (beta) / Auto.
- `~/.config/cmux/cmux.json` key + docs update.
- Telemetry (debug-log): time-to-first-paint, time-to-interactive, web-content-process crash counts.
- All entrypoints funnel through one panel-creation site (shared-behavior policy).
- Deprecation: keep old path for one release after CM6 default; remove in the release after that.

Exit criteria: CM6 default-on for one release cycle with no escalations.

## Stage 7 — Tests

Per `CLAUDE.md` test policy — behavior over source-string asserts:

- Unit: language detector (extension/shebang/filename specials).
- Integration (`tests_v2/`): open fixture file, assert renderer state via a Debug-only `cmuxd` socket command `panel.codeViewerState`.
- Diff: open before/after fixtures, hunk count matches `git diff --numstat`.
- Big-file guard: 10 MB fixture, banner appears, interactive in < 500 ms.
- Run via `gh workflow run test-e2e.yml`.

## Stage 8 — Future / nice-to-haves (separate roadmap)

- LSP bridge: stream `swift-lsp`, `gopls` into CM6 via `codemirror-languageserver` over a WebSocket served by `cmuxd`.
- Vim mode behind a setting (`@replit/codemirror-vim`).
- Hunk stage/unstage (`git apply --cached`) inside diff view.
- Inline blame gutter.
- Tree-sitter via `@codemirror/lang-textmate` adapter for grammars CM6 doesn't ship.

---

## Dependency order

- 0 blocks 1.
- 1 blocks 2, 3, 4, 5.
- 2 and 3 can land in parallel.
- 4 depends on 1 but is otherwise independent.
- 5 lands any time after 1.
- 6 needs 1 + 3 minimally; 4 is preferable.
- 7 is written inline with each stage.

## Risks

1. Web-content-process crashes — reuse markdown panel's recovery scaffolding.
2. Save correctness — JS owns buffer; Swift owns the file. Atomic write stays in Swift.
3. Typing latency under split-pane churn — coalesce theme/font reconfigures.
4. Bundle size growth — add a CI gate failing the build if `code-viewer.js.deflate` exceeds ~500 KB.
5. Binary / generated files — define and document fallback ("file too large / binary; summary only").

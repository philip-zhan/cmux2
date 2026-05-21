# Source Control tab plan

## Goal

Add a VSCode-style "Source Control" tab to the right sidebar that lists changed
files in the active workspace and opens a file in diff mode when clicked.

## Scope (v1)

Read-only changed-file list grouped by status (Staged / Changes / Untracked),
plus a per-file context menu with Discard Changes, Reveal in Files, and Copy
Path. No staging/commit. Clicking a file opens it in diff mode.

## Approach

Diff opens inside the existing `FilePreviewPanel` via a new `diffAgainstHead`
mode that loads content through `CodeViewerGitDiffSource` and feeds the
CodeMirror `MergeView` in the web viewer.

## Phases

### Phase 1 — Source Control tab shell
- Add `.sourceControl` to `RightSidebarMode` (`Sources/RightSidebarPanelView.swift`):
  enum case, `label`, `symbolName` (`arrow.triangle.branch`), `shortcutAction`.
- New switch case in `contentForMode` -> `SourceControlPanelView`.
- Add `.switchRightSidebarToSourceControl` to `KeyboardShortcutSettings`,
  `cmux.json` config, and shortcut docs.
- Register command palette entry.
- Localized strings in `Resources/Localizable.xcstrings` (EN + JA).

### Phase 2 — Git status model (`SourceControlStore`)
- `@MainActor final class SourceControlStore: ObservableObject`.
- Bound to the active `Workspace.currentDirectory`.
- `@Published var changes: [GitChange]` value type.
- `refresh()` runs `git status --porcelain` off-main, parses staged / unstaged
  / untracked groups.
- Auto-refresh via `FileExplorerDirectoryWatcher` on `.git/` + working tree,
  debounced; refresh on tab visible and workspace switch.
- `discard(_:)` — `git checkout --` for tracked, file delete for untracked.

### Phase 3 — `SourceControlPanelView`
- Grouped sections; rows obey the snapshot-boundary policy (value snapshots +
  closure action bundle, no store reference below the ForEach).
- Row: icon, name, dimmed path, colored status badge.
- Click -> open diff. Context menu: Discard / Reveal / Copy Path.
- Header with branch name + refresh; empty state.

### Phase 4 — Diff mode in `FilePreviewPanel`
- Add `diffAgainstHead` to `FilePreviewPanel` and `Workspace.openFileDiffSurfaces(...)`.
- Load via `CodeViewerGitDiffSource`, feed `diffOriginal`/`diffModified` to the
  web viewer's `MergeView`.
- Promote wiring out of the DEBUG `CodeMirrorSpike` into production.
- Persist `diffMode` in the panel session snapshot.

### Phase 5 — Polish & tests
- Behavior tests for `SourceControlStore` parsing and discard.
- Extend `CodeViewerGitDiffSourceTests` for the new open path.
- Build via `reload.sh --tag source-control --launch` and verify.

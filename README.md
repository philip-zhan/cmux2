<h1 align="center">cmux2</h1>
<p align="center">A Ghostty-based macOS terminal with vertical tabs and notifications for AI coding agents</p>
<p align="center"><em>This fork: cmux with a built-in editor and git diff</em></p>

<p align="center">
  <a href="https://github.com/philip-zhan/cmux2/releases/latest/download/cmux-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="Download cmux for macOS" width="180" />
  </a>
</p>

> ## ⚠️ This is a fork
>
> This repository ([`philip-zhan/cmux2`](https://github.com/philip-zhan/cmux2)) is a **fork** of the
> original [**cmux**](https://github.com/manaflow-ai/cmux) by Manaflow. It tracks upstream and layers
> on a few extra features (listed below). It ships as a separate app with its own bundle ID and
> control socket, so it runs alongside the original.
>
> **For everything about cmux — what it is, why it exists, full feature list, install instructions,
> docs, and community — read the original project's README:**
>
> ### 👉 [github.com/manaflow-ai/cmux](https://github.com/manaflow-ai/cmux#readme)
>
> This README only documents what this fork *adds* on top of upstream.

## Why this fork

I love cmux, but two missing pieces kept pulling me out of it:

- **No built-in editor.** To view or make a small change to a file, I had to drop into a terminal
  editor like Vim or open the project in a separate app — both break the flow of working next to a
  coding agent.
- **No source control view.** Reviewing what an agent changed meant running `git` commands by hand
  or switching to another tool.

These aren't just my pain points — they're some of the most-requested features upstream.

**Built-in editor:**

- [#137 — Text editor pane type](https://github.com/manaflow-ai/cmux/issues/137)
- [#648 — Add VSCode/Cursor like code editor as a type of screen](https://github.com/manaflow-ai/cmux/issues/648)
- [#4465 — Could you integrate a lightweight editor? … I need features like a file tree](https://github.com/manaflow-ai/cmux/issues/4465)
- [#3344 — Integrated Code Workspace: File Explorer & Navigation Surface](https://github.com/manaflow-ai/cmux/issues/3344)
- [#1197 — Add a button to open a specific workspace in an editor](https://github.com/manaflow-ai/cmux/issues/1197)
- [#1544 — Cmd+click on file paths should open in IDE](https://github.com/manaflow-ai/cmux/issues/1544)
- [#2599 — Opening markdown file in a panel](https://github.com/manaflow-ai/cmux/issues/2599)

**Source control:**

- [#2526 — Is there a way to view Git changes?](https://github.com/manaflow-ai/cmux/issues/2526)
- [#609 — Add inline diff / code review panel for reviewing agent-generated changes](https://github.com/manaflow-ai/cmux/issues/609)
- [#678 — Built-in color-coded diff/changed-files panel per Claude session](https://github.com/manaflow-ai/cmux/issues/678)
- [#959 — Sidebar: show git status counts (uncommitted changes, ahead/behind)](https://github.com/manaflow-ai/cmux/issues/959)

This fork exists to fill those gaps. As a general principle, the editor and source control features
**try to stay close to VS Code's UX** — familiar keybindings, a familiar quick-open, and a familiar
Source Control panel — so there's nothing new to learn.

## Fork additions

<table>
<tr>
<td width="40%" valign="middle">
<h3>Built-in editor (CodeMirror 6)</h3>
Open files directly in a native editor pane without leaving cmux. The editor is built on
CodeMirror 6, with markdown editing plus image and PDF preview.
</td>
<td width="60%" valign="middle">
<ul>
<li>Native editor pane powered by CodeMirror 6</li>
<li>Markdown panels that default to edit-source mode</li>
<li>Image and PDF preview panes</li>
</ul>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Quick file open (⌘P)</h3>
VS Code-style quick file open straight from the command palette, so you can jump to any file in
the workspace by name.
</td>
<td width="60%" valign="middle">
<ul>
<li>⌘P quick file open from the command palette</li>
<li>Right sidebar file explorer (⌥⌘B to toggle)</li>
</ul>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Syntax highlighting</h3>
Syntax-highlighted code viewer with git diff support, plus VS Code-like floating search inside the
editor pane.
</td>
<td width="60%" valign="middle">
<ul>
<li>Syntax-highlighted code viewer</li>
<li>Git diff support</li>
<li>VS Code-like floating in-file search</li>
</ul>
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Source Control tab</h3>
A Source Control tab in the right sidebar surfaces git status for the workspace so you can review
changes without leaving cmux.
</td>
<td width="60%" valign="middle">
<ul>
<li>Source Control tab in the right sidebar</li>
<li>Live git status for the current workspace</li>
</ul>
</td>
</tr>
</table>

## Keyboard Shortcuts

### Workspaces

| Shortcut | Action |
|----------|--------|
| ⌘ N | New workspace |
| ⌘ 1–8 | Jump to workspace 1–8 |
| ⌘ 9 | Jump to last workspace |
| ⌃ ⌘ ] | Next workspace |
| ⌃ ⌘ [ | Previous workspace |
| ⌘ ⇧ W | Close workspace |
| ⌘ ⇧ R | Rename workspace |
| ⌥ ⌘ E | Edit workspace description |
| ⌘ B | Toggle sidebar |
| ⌥ ⌘ B | Toggle right sidebar |
| ⌘ ⇧ E | Toggle right sidebar focus |

### Surfaces

| Shortcut | Action |
|----------|--------|
| ⌘ T | New surface |
| ⌘ ⇧ ] | Next surface |
| ⌘ ⇧ [ | Previous surface |
| ⌃ Tab | Next surface |
| ⌃ ⇧ Tab | Previous surface |
| ⌃ 1–8 | Jump to surface 1–8 |
| ⌃ 9 | Jump to last surface |
| ⌘ W | Close surface |

### Split Panes

| Shortcut | Action |
|----------|--------|
| ⌘ D | Split right |
| ⌘ ⇧ D | Split down |
| ⌥ ⌘ ← → ↑ ↓ | Focus pane directionally |
| ⌘ ⇧ H | Flash focused panel |

### Browser

Browser developer-tool shortcuts follow Safari defaults and are customizable in `Settings → Keyboard Shortcuts`.
Command palette navigation shortcuts, including ⌃ P, are also customizable and can be cleared so the keypress reaches the active terminal.

| Shortcut | Action |
|----------|--------|
| ⌘ ⇧ L | Open browser in split |
| ⌘ L | Focus address bar |
| ⌘ [ | Back |
| ⌘ ] | Forward |
| ⌘ R | Reload page |
| ⌥ ⌘ I | Toggle Developer Tools (Safari default) |
| ⌥ ⌘ C | Show JavaScript Console (Safari default) |

### Notifications

| Shortcut | Action |
|----------|--------|
| ⌘ I | Show notifications panel |
| ⌘ ⇧ U | Jump to latest unread |
| ⌥ ⌘ U | Toggle current item unread state |
| ⌃ ⌘ U | Mark current item as oldest unread and jump to next latest unread |

### Find

| Shortcut | Action |
|----------|--------|
| ⌘ F | Find |
| ⌘ ⇧ F | Find in directory |
| ⌘ G / ⌥ ⌘ G | Find next / previous |
| ⌥ ⌘ ⇧ F | Hide find bar |
| ⌘ E | Use selection for find |

### Editor

Keybindings follow VS Code conventions.

| Shortcut | Action |
|----------|--------|
| ⌘ P | Quick file open |
| ⌘ S | Save file |
| ⌘ F | Find in file |
| ⌘ G / ⇧ ⌘ G | Find next / previous |
| ⌘ Z / ⇧ ⌘ Z | Undo / redo |
| ⌘ A | Select all |
| ⌘ / | Toggle line comment |
| ⌥ ↑ / ⌥ ↓ | Move line up / down |
| Esc | Close find bar |

### Terminal

| Shortcut | Action |
|----------|--------|
| ⌘ K | Clear scrollback |
| ⌘ C | Copy (with selection) |
| ⌘ V | Paste |
| ⌘ + / ⌘ - | Increase / decrease font size |
| ⌘ 0 | Reset font size |

### Window

| Shortcut | Action |
|----------|--------|
| ⌘ ⇧ N | New window |
| ⌘ ⇧ O | Reopen previous session |
| ⌘ , | Settings |
| ⌘ ⇧ , | Reload configuration |
| ⌘ Q | Quit |

## License

cmux is open source under [GPL-3.0-or-later](LICENSE).

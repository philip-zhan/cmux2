import AppKit
import SwiftUI

/// Closure bundle handed to source-control rows. Keeps row views free of any
/// reference to `SourceControlStore`, per the snapshot-boundary policy.
struct SourceControlRowActions {
    let onOpenDiff: (SourceControlChange) -> Void
    let onOpenFile: (SourceControlChange) -> Void
    let onDiscard: (SourceControlChange) -> Void
    let onRevealInFinder: (SourceControlChange) -> Void
    let onCopyRelativePath: (SourceControlChange) -> Void
    let onCopyAbsolutePath: (SourceControlChange) -> Void
}

/// Source Control sidebar tab. Lists changed files grouped by staged /
/// unstaged / untracked and opens a file in diff mode when clicked.
struct SourceControlPanelView: View {
    let directory: String?
    let onOpenDiff: (String) -> Void
    let onOpenFile: (String) -> Void

    @StateObject private var store = SourceControlStore()
    @State private var pendingDiscard: SourceControlChange?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            store.setDirectory(directory)
            store.refresh()
        }
        .onChange(of: directory) { _, newValue in
            store.setDirectory(newValue)
        }
        .alert(
            String(localized: "sourceControl.discard.title", defaultValue: "Discard Changes"),
            isPresented: discardAlertBinding,
            presenting: pendingDiscard
        ) { change in
            Button(role: .destructive) {
                store.discard(change)
                pendingDiscard = nil
            } label: {
                Text(String(localized: "sourceControl.discard.confirm", defaultValue: "Discard"))
            }
            Button(role: .cancel) {
                pendingDiscard = nil
            } label: {
                Text(String(localized: "sourceControl.discard.cancel", defaultValue: "Cancel"))
            }
        } message: { change in
            Text(discardMessage(for: change))
        }
        .accessibilityIdentifier("SourceControlPanel")
    }

    private var discardAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDiscard != nil },
            set: { if !$0 { pendingDiscard = nil } }
        )
    }

    private func discardMessage(for change: SourceControlChange) -> String {
        if change.kind == .untracked {
            return String.localizedStringWithFormat(
                String(
                    localized: "sourceControl.discard.message.untracked",
                    defaultValue: "Delete the untracked file \"%@\"? This cannot be undone."
                ),
                change.displayName
            )
        }
        return String.localizedStringWithFormat(
            String(
                localized: "sourceControl.discard.message.tracked",
                defaultValue: "Discard all changes to \"%@\"? This cannot be undone."
            ),
            change.displayName
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(branchTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if store.totalChangeCount > 0 {
                Text("\(store.totalChangeCount)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }
            Spacer(minLength: 0)
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(String(localized: "sourceControl.refresh.tooltip", defaultValue: "Refresh"))
            .accessibilityIdentifier("SourceControlPanel.refreshButton")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var branchTitle: String {
        if let branch = store.branchName, !branch.isEmpty {
            return branch
        }
        return String(localized: "sourceControl.noBranch", defaultValue: "Source Control")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.directory == nil {
            placeholder(
                systemImage: "folder",
                text: String(
                    localized: "sourceControl.empty.noWorkspace",
                    defaultValue: "Open a workspace to see source control."
                )
            )
        } else if store.hasLoadedOnce && !store.isRepository {
            placeholder(
                systemImage: "arrow.triangle.branch",
                text: String(
                    localized: "sourceControl.empty.notRepo",
                    defaultValue: "This workspace is not a Git repository."
                )
            )
        } else if store.hasLoadedOnce && !store.hasChanges {
            placeholder(
                systemImage: "checkmark.circle",
                text: String(
                    localized: "sourceControl.empty.noChanges",
                    defaultValue: "No changes."
                )
            )
        } else if !store.hasLoadedOnce {
            placeholder(
                systemImage: "clock",
                text: String(localized: "sourceControl.loading", defaultValue: "Loading…")
            )
        } else {
            changeList
        }
    }

    private var changeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                section(
                    title: String(localized: "sourceControl.section.staged", defaultValue: "Staged Changes"),
                    changes: store.stagedChanges
                )
                section(
                    title: String(localized: "sourceControl.section.changes", defaultValue: "Changes"),
                    changes: store.unstagedChanges
                )
                section(
                    title: String(localized: "sourceControl.section.untracked", defaultValue: "Untracked"),
                    changes: store.untrackedChanges
                )
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func section(title: String, changes: [SourceControlChange]) -> some View {
        if !changes.isEmpty {
            Section {
                ForEach(changes) { change in
                    SourceControlRow(change: change, actions: rowActions)
                }
            } header: {
                SourceControlSectionHeader(title: title, count: changes.count)
            }
        }
    }

    private func placeholder(systemImage: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Row actions

    private var rowActions: SourceControlRowActions {
        SourceControlRowActions(
            onOpenDiff: { change in onOpenDiff(change.absolutePath) },
            onOpenFile: { change in onOpenFile(change.absolutePath) },
            onDiscard: { change in pendingDiscard = change },
            onRevealInFinder: { change in revealInFinder(change) },
            onCopyRelativePath: { change in copyToPasteboard(change.relativePath) },
            onCopyAbsolutePath: { change in copyToPasteboard(change.absolutePath) }
        )
    }

    private func revealInFinder(_ change: SourceControlChange) {
        let url = URL(fileURLWithPath: change.absolutePath)
        if FileManager.default.fileExists(atPath: change.absolutePath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}

// MARK: - Section header

private struct SourceControlSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundColor(.secondary.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

// MARK: - Row

/// Pure value view: holds only the immutable change snapshot and the closure
/// bundle. No `SourceControlStore` reference, satisfying the snapshot boundary.
private struct SourceControlRow: View {
    let change: SourceControlChange
    let actions: SourceControlRowActions

    @State private var isHovered = false

    var body: some View {
        Button {
            actions.onOpenDiff(change)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                Text(change.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !change.directoryPath.isEmpty {
                    Text(change.directoryPath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                Text(change.kind.badgeLetter)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundColor(badgeColor)
                    .frame(width: 14)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(change.relativePath)
        .contextMenu {
            Button {
                actions.onOpenDiff(change)
            } label: {
                Text(String(localized: "sourceControl.action.openDiff", defaultValue: "Open Diff"))
            }
            Button {
                actions.onOpenFile(change)
            } label: {
                Text(String(localized: "sourceControl.action.openFile", defaultValue: "Open File"))
            }
            Divider()
            Button {
                actions.onRevealInFinder(change)
            } label: {
                Text(String(localized: "sourceControl.action.revealInFinder", defaultValue: "Reveal in Finder"))
            }
            Button {
                actions.onCopyRelativePath(change)
            } label: {
                Text(String(localized: "sourceControl.action.copyRelativePath", defaultValue: "Copy Relative Path"))
            }
            Button {
                actions.onCopyAbsolutePath(change)
            } label: {
                Text(String(localized: "sourceControl.action.copyAbsolutePath", defaultValue: "Copy Path"))
            }
            Divider()
            Button(role: .destructive) {
                actions.onDiscard(change)
            } label: {
                Text(String(localized: "sourceControl.action.discard", defaultValue: "Discard Changes"))
            }
        }
        .accessibilityIdentifier("SourceControlRow.\(change.relativePath)")
    }

    private var iconName: String {
        switch change.kind {
        case .deleted: return "trash"
        case .added, .untracked: return "doc.badge.plus"
        case .renamed, .copied: return "arrow.right.doc.on.clipboard"
        case .conflicted: return "exclamationmark.triangle"
        case .typeChanged: return "doc"
        case .modified: return "doc.text"
        }
    }

    private var badgeColor: Color {
        switch change.kind {
        case .modified, .typeChanged: return .orange
        case .added, .copied: return .green
        case .untracked: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .conflicted: return .red
        }
    }
}

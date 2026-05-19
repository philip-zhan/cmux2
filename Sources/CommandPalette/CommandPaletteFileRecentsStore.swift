import Combine
import Foundation

/// Persisted "recently opened" files per workspace, surfaced by the command palette
/// `.files` scope when the user opens it with an empty query. Stored as JSON in
/// `~/Library/Application Support/cmux/file-recents/<workspaceID>.json`.
@MainActor
final class CommandPaletteFileRecentsStore: ObservableObject {
    static let shared = CommandPaletteFileRecentsStore()

    static let maxEntriesPerWorkspace = 50

    struct Entry: Codable, Equatable, Sendable {
        /// Path relative to the workspace root that was active when the file was opened.
        let relativePath: String
        let absolutePath: String
        var lastOpenedAt: TimeInterval
        var openCount: Int
    }

    /// Bump on every mutation so views can invalidate cached corpora derived from this store.
    @Published private(set) var revision: UInt64 = 0

    private var cache: [UUID: [Entry]] = [:]
    private var loadedWorkspaces: Set<UUID> = []
    private let directoryURL: URL?

    init() {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let url = appSupport
                .appendingPathComponent("cmux", isDirectory: true)
                .appendingPathComponent("file-recents", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            self.directoryURL = url
        } else {
            self.directoryURL = nil
        }
    }

    /// Returns the recents for a workspace, most-recently-opened first. Lazily loads
    /// the file on first access; subsequent reads are in-memory.
    func recents(workspaceID: UUID) -> [Entry] {
        loadIfNeeded(workspaceID: workspaceID)
        return cache[workspaceID] ?? []
    }

    /// Records that `absolutePath` was opened. `rootPath` is the workspace root at the
    /// time of the open so we can store a stable relative path even if the workspace
    /// later `cd`s elsewhere. Passing an empty or unrelated `rootPath` falls back to
    /// the absolute path as the relative path.
    func recordOpen(
        workspaceID: UUID,
        rootPath: String,
        absolutePath: String,
        now: Date = Date()
    ) {
        loadIfNeeded(workspaceID: workspaceID)
        let relativePath = Self.relativize(absolutePath: absolutePath, rootPath: rootPath)
        var entries = cache[workspaceID] ?? []
        let timestamp = now.timeIntervalSince1970
        if let index = entries.firstIndex(where: { $0.absolutePath == absolutePath }) {
            entries[index].lastOpenedAt = timestamp
            entries[index].openCount += 1
        } else {
            entries.insert(
                Entry(
                    relativePath: relativePath,
                    absolutePath: absolutePath,
                    lastOpenedAt: timestamp,
                    openCount: 1
                ),
                at: 0
            )
        }
        entries.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        if entries.count > Self.maxEntriesPerWorkspace {
            entries.removeLast(entries.count - Self.maxEntriesPerWorkspace)
        }
        cache[workspaceID] = entries
        revision &+= 1
        persist(workspaceID: workspaceID, entries: entries)
    }

    private func loadIfNeeded(workspaceID: UUID) {
        guard !loadedWorkspaces.contains(workspaceID) else { return }
        loadedWorkspaces.insert(workspaceID)
        guard let url = fileURL(for: workspaceID),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return
        }
        cache[workspaceID] = entries
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func persist(workspaceID: UUID, entries: [Entry]) {
        guard let url = fileURL(for: workspaceID) else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(for workspaceID: UUID) -> URL? {
        directoryURL?.appendingPathComponent("\(workspaceID.uuidString).json")
    }

    private static func relativize(absolutePath: String, rootPath: String) -> String {
        guard !rootPath.isEmpty else { return absolutePath }
        let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if absolutePath.hasPrefix(rootWithSlash) {
            return String(absolutePath.dropFirst(rootWithSlash.count))
        }
        return absolutePath
    }
}

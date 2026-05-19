import Combine
import Darwin
import Foundation

/// Snapshot of a `fd`-produced file list for a single workspace root. Consumed by the
/// command palette `.files` scope to populate its search corpus.
struct CommandPaletteFileIndexSnapshot: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case idle
        case indexing
        case ready
        case failed(reason: Reason)
    }

    enum Reason: Sendable, Equatable {
        case fdNotInstalled
        case fdFailed(exitCode: Int32)
        case cancelled
    }

    struct Entry: Sendable, Equatable, Hashable {
        /// Path relative to `rootPath`, using POSIX separators. Never empty.
        let relativePath: String
        /// Final path component of `relativePath`.
        let fileName: String
    }

    let rootPath: String
    let entries: [Entry]
    let status: Status
    let truncated: Bool
    let generation: UInt64

    static let empty = CommandPaletteFileIndexSnapshot(
        rootPath: "",
        entries: [],
        status: .idle,
        truncated: false,
        generation: 0
    )
}

@MainActor
final class CommandPaletteFileIndexer: ObservableObject {
    static let shared = CommandPaletteFileIndexer()

    /// Hard cap on the number of entries kept per snapshot. fd can produce millions of
    /// rows in pathological repos; the palette can't usefully display more than a few
    /// thousand, so we stop reading once we hit this.
    static let maxEntries = 200_000

    private struct FdExecutable {
        let url: URL
    }

    private struct Request: Equatable {
        let rootPath: String
    }

    private var generation: UInt64 = 0
    private var process: Process?
    private var readTask: Task<Void, Never>?
    private var activeRequest: Request?
    @Published private(set) var currentSnapshot: CommandPaletteFileIndexSnapshot = .empty

    /// Begin (or reuse) an index build for `rootPath`. If the root matches the active
    /// request and a build is in flight or complete, this is a no-op.
    func requestIndex(forRootPath rootPath: String) {
        let trimmed = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancel(reason: .cancelled)
            currentSnapshot = .empty
            return
        }

        let request = Request(rootPath: trimmed)
        if activeRequest == request, process?.isRunning == true {
            return
        }
        if activeRequest == request, currentSnapshot.status == .ready {
            return
        }

        cancel(reason: .cancelled)
        activeRequest = request

        guard let fd = Self.fdExecutable() else {
            currentSnapshot = CommandPaletteFileIndexSnapshot(
                rootPath: trimmed,
                entries: [],
                status: .failed(reason: .fdNotInstalled),
                truncated: false,
                generation: advanceGeneration()
            )
            return
        }

        let buildGeneration = advanceGeneration()
        currentSnapshot = CommandPaletteFileIndexSnapshot(
            rootPath: trimmed,
            entries: [],
            status: .indexing,
            truncated: false,
            generation: buildGeneration
        )
        spawn(fd: fd, rootPath: trimmed, generation: buildGeneration)
    }

    /// Drop any in-flight work and reset state. Safe to call from any path.
    func reset() {
        cancel(reason: .cancelled)
        activeRequest = nil
        currentSnapshot = .empty
    }

    private func advanceGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func cancel(reason: CommandPaletteFileIndexSnapshot.Reason) {
        readTask?.cancel()
        readTask = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        _ = reason
    }

    private func spawn(fd: FdExecutable, rootPath: String, generation buildGeneration: UInt64) {
        let process = Process()
        process.executableURL = fd.url
        // `--print0` separates results with NUL so paths with newlines are safe.
        // `--hidden` includes dotfiles but `--exclude .git` skips the VCS metadata
        // directory, which is rarely useful in a file picker and is huge.
        process.arguments = [
            "--type", "f",
            "--color", "never",
            "--hidden",
            "--exclude", ".git",
            "--print0",
            ".",
            rootPath,
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            currentSnapshot = CommandPaletteFileIndexSnapshot(
                rootPath: rootPath,
                entries: [],
                status: .failed(reason: .fdFailed(exitCode: -1)),
                truncated: false,
                generation: buildGeneration
            )
            return
        }
        self.process = process

        let outputHandle = stdout.fileHandleForReading
        let errorHandle = stderr.fileHandleForReading
        let maxEntries = Self.maxEntries

        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = await Self.readEntries(
                outputHandle: outputHandle,
                errorHandle: errorHandle,
                rootPath: rootPath,
                maxEntries: maxEntries
            )
            process.waitUntilExit()
            let exitCode = process.terminationStatus
            await MainActor.run {
                guard let self else { return }
                guard self.generation == buildGeneration else { return }
                self.process = nil
                self.readTask = nil

                let status: CommandPaletteFileIndexSnapshot.Status
                if Task.isCancelled {
                    status = .failed(reason: .cancelled)
                } else if exitCode != 0 {
                    status = .failed(reason: .fdFailed(exitCode: exitCode))
                } else {
                    status = .ready
                }

                self.currentSnapshot = CommandPaletteFileIndexSnapshot(
                    rootPath: rootPath,
                    entries: result.entries,
                    status: status,
                    truncated: result.truncated,
                    generation: buildGeneration
                )
            }
        }
    }

    private static func readEntries(
        outputHandle: FileHandle,
        errorHandle: FileHandle,
        rootPath: String,
        maxEntries: Int
    ) async -> (entries: [CommandPaletteFileIndexSnapshot.Entry], truncated: Bool) {
        // Drain stderr to /dev/null so a large stream doesn't block fd's exit.
        let drainTask = Task.detached(priority: .utility) {
            while true {
                let data = errorHandle.availableData
                if data.isEmpty { break }
            }
        }
        defer { drainTask.cancel() }

        var entries: [CommandPaletteFileIndexSnapshot.Entry] = []
        entries.reserveCapacity(min(maxEntries, 4096))
        var buffer = Data()
        var truncated = false
        let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        while !truncated {
            let chunk = outputHandle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nulRange = buffer.range(of: Data([0])) {
                let slice = buffer.subdata(in: 0..<nulRange.lowerBound)
                buffer.removeSubrange(0..<nulRange.upperBound)
                guard !slice.isEmpty,
                      let absolute = String(data: slice, encoding: .utf8) else {
                    continue
                }
                let relative: String
                if absolute.hasPrefix(rootWithSlash) {
                    relative = String(absolute.dropFirst(rootWithSlash.count))
                } else if absolute == rootPath {
                    continue
                } else {
                    relative = absolute
                }
                guard !relative.isEmpty else { continue }
                let fileName = (relative as NSString).lastPathComponent
                entries.append(.init(relativePath: relative, fileName: fileName))
                if entries.count >= maxEntries {
                    truncated = true
                    break
                }
            }
            if Task.isCancelled { break }
        }

        return (entries, truncated)
    }

    private static func fdExecutable() -> FdExecutable? {
        let fileManager = FileManager.default
        for path in ["/opt/homebrew/bin/fd", "/usr/local/bin/fd", "/usr/bin/fd"]
            where fileManager.isExecutableFile(atPath: path)
        {
            return FdExecutable(url: URL(fileURLWithPath: path))
        }
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":", omittingEmptySubsequences: true) {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent("fd").path
            if fileManager.isExecutableFile(atPath: path) {
                return FdExecutable(url: URL(fileURLWithPath: path))
            }
        }
        return nil
    }
}

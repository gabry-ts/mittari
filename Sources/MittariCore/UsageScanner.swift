import Foundation

/// Finds and incrementally reads Claude Code and Codex logs. Remembers a byte offset per
/// file, so a refresh only parses appended lines. Not thread-safe: use it from one queue.
public final class UsageScanner {
    public struct Folder: Hashable, Sendable {
        public var url: URL
        public var exists: Bool
        public var fileCount: Int

        public init(url: URL, exists: Bool, fileCount: Int) {
            self.url = url
            self.exists = exists
            self.fileCount = fileCount
        }
    }

    public let claudeRoots: [URL]
    public let codexRoot: URL?
    /// How far back logs are read; older files and entries are skipped.
    public var lookback: TimeInterval

    public private(set) var ledger = UsageLedger()
    public private(set) var lastScan: Date?
    public private(set) var lastScanDuration: TimeInterval = 0

    private struct FileState {
        var offset: UInt64 = 0
        var size: UInt64 = 0
    }

    private var claudeFiles: [String: FileState] = [:]
    private var codexFiles: [String: FileState] = [:]
    private var codexParsers: [String: CodexLogParser] = [:]
    /// Every `cwd` seen per project folder, first seen first.
    private var cwds: [String: [String]] = [:]
    private var folderStats: [URL: Int] = [:]

    public init(claudeRoots: [URL], codexRoot: URL?, lookback: TimeInterval = 366 * 86_400) {
        self.claudeRoots = claudeRoots
        self.codexRoot = codexRoot
        self.lookback = lookback
    }

    /// The standard locations: `$CLAUDE_CONFIG_DIR` (comma-separated), `~/.config/claude`
    /// and `~/.claude`, each with a `projects` folder, plus `$CODEX_HOME` or `~/.codex`.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> UsageScanner {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var bases: [URL] = []
        if let custom = environment["CLAUDE_CONFIG_DIR"] {
            bases += custom.split(separator: ",").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)) }
        }
        bases += [home.appendingPathComponent(".config/claude"), home.appendingPathComponent(".claude")]
        var seen = Set<String>()
        let roots = bases.map { $0.appendingPathComponent("projects").standardizedFileURL }.filter { seen.insert($0.path).inserted }
        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        return UsageScanner(claudeRoots: roots, codexRoot: codexHome.appendingPathComponent("sessions"))
    }

    /// Folders to watch for changes.
    public var watchedFolders: [URL] { claudeRoots + [codexRoot].compactMap { $0 } }

    public var folders: [Folder] {
        watchedFolders.map { url in
            Folder(url: url, exists: ProjectName.defaultExists(url.path), fileCount: folderStats[url] ?? 0)
        }
    }

    public var codexSessions: [CodexSession] { codexParsers.values.map(\.session) }

    /// Readable names for the project folders seen so far.
    public var projectNames: [String: String] {
        var names: [String: String] = [:]
        for (folder, seen) in cwds {
            names[folder] = ProjectName.displayName(folder: folder, cwds: seen)
        }
        return names
    }

    /// Forgets everything, so the next scan reads every file from the start.
    public func reset() {
        ledger = UsageLedger()
        claudeFiles = [:]
        codexFiles = [:]
        codexParsers = [:]
        cwds = [:]
    }

    /// Walks every folder and reads whatever changed.
    public func scanAll(now: Date = Date()) {
        let started = Date()
        let cutoff = now.addingTimeInterval(-lookback)
        for root in claudeRoots {
            let files = logFiles(in: root)
            folderStats[root] = files.count
            for file in files where file.modified >= cutoff {
                readClaude(file.url, size: file.size, root: root)
            }
        }
        if let codexRoot {
            let files = logFiles(in: codexRoot)
            folderStats[codexRoot] = files.count
            for file in files where file.modified >= cutoff {
                readCodex(file.url, size: file.size)
            }
        }
        ledger.prune(before: cutoff)
        ledger.sort()
        lastScan = now
        lastScanDuration = Date().timeIntervalSince(started)
    }

    /// Reads only the given files, as reported by a file system watcher.
    public func scan(paths: [String], now: Date = Date()) {
        for path in paths where path.hasSuffix(".jsonl") {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let size = UInt64(values.fileSize ?? 0)
            if let root = claudeRoots.first(where: { url.path.hasPrefix($0.path + "/") }) {
                readClaude(url, size: size, root: root)
            } else if let codexRoot, url.path.hasPrefix(codexRoot.path + "/") {
                readCodex(url, size: size)
            }
        }
        ledger.sort()
        lastScan = now
    }

    // MARK: Reading

    private func readClaude(_ url: URL, size: UInt64, root: URL) {
        var state = claudeFiles[url.path] ?? FileState()
        // A file that shrank was rewritten: read it again (deduplication absorbs repeats).
        if size < state.offset { state = FileState() }
        guard size != state.offset else { return }
        let relative = url.path.dropFirst(root.path.count + 1)
        let folder = String(relative.split(separator: "/").first ?? "")
        var seenCwds = cwds[folder] ?? []
        let newOffset = LineReader.read(url, from: state.offset) { line in
            guard ClaudeLog.mightContainUsage(line) else { return }
            // Decoding leaves autoreleased objects behind; drain them per line, or a first
            // scan of a few gigabytes of logs peaks at gigabytes of memory.
            autoreleasepool {
                guard let record = ClaudeLog.parse(line: Data(line), project: folder) else { return }
                ledger.add(record)
                if let cwd = record.cwd, seenCwds.count < 8, !seenCwds.contains(cwd) {
                    seenCwds.append(cwd)
                }
            }
        }
        cwds[folder] = seenCwds
        state.offset = newOffset ?? size
        state.size = size
        claudeFiles[url.path] = state
    }

    private func readCodex(_ url: URL, size: UInt64) {
        var state = codexFiles[url.path] ?? FileState()
        var parser = codexParsers[url.path] ?? CodexLogParser(fileName: url.lastPathComponent)
        if size < state.offset {
            state = FileState()
            parser = CodexLogParser(fileName: url.lastPathComponent)
        }
        guard size != state.offset || codexParsers[url.path] == nil else { return }
        let newOffset = LineReader.read(url, from: state.offset) { line in
            autoreleasepool { parser.consume(Data(line)) }
        }
        state.offset = newOffset ?? size
        state.size = size
        codexFiles[url.path] = state
        codexParsers[url.path] = parser
    }

    private struct LogFile {
        var url: URL
        var size: UInt64
        var modified: Date
    }

    private func logFiles(in root: URL) -> [LogFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var files: [LogFile] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            files.append(LogFile(url: url.standardizedFileURL, size: UInt64(values.fileSize ?? 0),
                                 modified: values.contentModificationDate ?? .distantPast))
        }
        return files
    }
}

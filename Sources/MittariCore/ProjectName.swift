import Foundation

/// Claude Code stores each project's transcripts in a folder named after its path, with
/// every character other than a letter or digit replaced by `-`. That is lossy (`-` in a
/// name looks like a separator), so the readable name comes from the `cwd` recorded in
/// the transcript whenever there is one.
public enum ProjectName {
    public static func encode(_ path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// Short name for a project folder: the last component of the `cwd` that encodes to
    /// the folder name, else of the first `cwd` seen, else a best-effort decode.
    public static func displayName(folder: String, cwds: [String], exists: (String) -> Bool = defaultExists) -> String {
        if let match = cwds.first(where: { encode($0) == folder }) ?? cwds.first {
            let name = (match as NSString).lastPathComponent
            if !name.isEmpty, name != "/" { return name }
        }
        return decode(folder: folder, exists: exists)
    }

    /// Rebuilds a path from a folder name by walking the file system: at each `-` it
    /// prefers a `/` when that prefix is an existing directory, else keeps the `-`. Falls
    /// back to the last dash-separated piece when nothing on disk matches.
    public static func decode(folder: String, exists: (String) -> Bool = defaultExists) -> String {
        let parts = folder.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1, parts[0].isEmpty else { return folder }
        var path = ""
        var current = ""
        var resolvedAny = false
        for part in parts.dropFirst() {
            if current.isEmpty {
                // An empty piece is a doubled dash: a hidden folder such as `.config`.
                current = part.isEmpty ? "." : part
                continue
            }
            if current == "." {
                current += part
                continue
            }
            let candidate = path + "/" + current
            if exists(candidate) {
                path = candidate
                current = part.isEmpty ? "." : part
                resolvedAny = true
            } else {
                // Either a literal "-" or a "." or "_" we can't tell apart; "-" is most common.
                current += "-" + part
            }
        }
        if resolvedAny, !current.isEmpty { return current }
        return parts.last(where: { !$0.isEmpty }) ?? folder
    }

    public static func defaultExists(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

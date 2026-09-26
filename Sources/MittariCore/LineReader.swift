import Foundation

/// Reads a log file from a byte offset, one complete line at a time, so each refresh only
/// touches what was appended since the last one.
public enum LineReader {
    static let chunkSize = 4 << 20

    /// Calls `body` with each complete line after `offset` and returns the offset just
    /// past the last complete line; a trailing partial line is left for next time.
    /// Returns nil if the file can't be read.
    @discardableResult
    public static func read(_ url: URL, from offset: UInt64, body: (UnsafeRawBufferPointer) -> Void) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        var consumed = offset
        var pending = Data()
        while true {
            guard let chunk = autoreleasepool(invoking: { try? handle.read(upToCount: chunkSize) }), !chunk.isEmpty else { break }
            pending.append(chunk)
            let used = pending.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                var start = 0
                while start < buffer.count,
                      let newline = memchr(base + start, 0x0A, buffer.count - start) {
                    let end = base.distance(to: UnsafeRawPointer(newline))
                    if end > start {
                        body(UnsafeRawBufferPointer(rebasing: buffer[start..<end]))
                    }
                    start = end + 1
                }
                return start
            }
            consumed += UInt64(used)
            pending.removeSubrange(0..<used)
        }
        return consumed
    }
}

import CoreServices
import Foundation

/// Reports which files changed under a set of folders, via FSEvents. Events are coalesced
/// by the system over `latency` seconds, so a busy log costs one callback, not hundreds.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let box: Box

    private final class Box {
        let handler: @Sendable ([String]) -> Void
        init(handler: @escaping @Sendable ([String]) -> Void) { self.handler = handler }
    }

    /// `handler` runs on `queue`, so it must not assume the main actor.
    init?(paths: [String], latency: TimeInterval, queue: DispatchQueue, handler: @escaping @Sendable ([String]) -> Void) {
        guard !paths.isEmpty else { return nil }
        box = Box(handler: handler)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
            box.handler((array as? [String] ?? []).prefix(count).map { $0 })
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            return nil
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

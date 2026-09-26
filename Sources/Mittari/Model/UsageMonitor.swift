import Foundation
import MittariCore
import Observation

/// Keeps the usage report fresh: a full rescan on a timer, plus quick incremental reads
/// of the files FSEvents reports as changed. Parsing runs on a background queue.
@MainActor
@Observable
final class UsageMonitor {
    private(set) var report = UsageReport(generatedAt: .now)
    private(set) var folders: [UsageScanner.Folder] = []
    private(set) var entryCount = 0
    private(set) var lastScan: Date?
    private(set) var lastScanDuration: TimeInterval = 0
    private(set) var isScanning = false
    /// Advances every 30 seconds, so countdowns redraw between reports.
    private(set) var now = Date()

    /// Called on the main actor after each new report.
    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored var prices = PriceBook.defaults {
        didSet { if prices != oldValue { refresh(full: false) } }
    }

    @ObservationIgnored private let worker: ScanWorker?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var clock: Timer?

    init() {
        worker = ScanWorker()
    }

    /// Mock monitor for offscreen snapshots.
    init(report: UsageReport, folders: [UsageScanner.Folder], entryCount: Int, now: Date) {
        worker = nil
        self.report = report
        self.folders = folders
        self.entryCount = entryCount
        self.now = now
        lastScan = now
        lastScanDuration = 1.8
    }

    func start(interval: TimeInterval) {
        guard let worker else { return }
        refresh(full: true)
        schedule(interval: interval)
        watcher = FolderWatcher(paths: worker.watchedPaths, latency: 5, queue: worker.queue) { [weak self] paths in
            // Already on the worker queue: read the changed files there, then publish.
            let result = worker.scanNow(paths: paths)
            Task { @MainActor in self?.publish(result) }
        }
        let clock = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        clock.tolerance = 5
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }

    func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(full: true) }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        clock?.invalidate()
        watcher = nil
    }

    /// Rescans (walking every folder when `full`) and rebuilds the report.
    func refresh(full: Bool, reset: Bool = false) {
        guard let worker else { return }
        isScanning = true
        let prices = prices
        worker.queue.async { [weak self] in
            let result = worker.scanNow(full: full, reset: reset, prices: prices)
            Task { @MainActor in self?.publish(result) }
        }
    }

    /// Forgets all offsets and reads every file again.
    func rescan() {
        refresh(full: true, reset: true)
    }

    private func publish(_ result: ScanWorker.Result) {
        isScanning = false
        report = result.report
        if folders != result.folders { folders = result.folders }
        entryCount = result.entryCount
        lastScan = result.report.generatedAt
        if let duration = result.fullScanDuration { lastScanDuration = duration }
        now = Date()
        onUpdate?()
    }
}

/// Owns the scanner; every call runs on `queue`.
final class ScanWorker: @unchecked Sendable {
    struct Result: Sendable {
        var report: UsageReport
        var folders: [UsageScanner.Folder]
        var entryCount: Int
        var fullScanDuration: TimeInterval?
    }

    let queue = DispatchQueue(label: "com.gabrielepartiti.mittari.scan", qos: .utility)
    private let scanner = UsageScanner.standard()
    private var prices = PriceBook.defaults

    var watchedPaths: [String] {
        scanner.watchedFolders.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Must be called on `queue`.
    func scanNow(full: Bool, reset: Bool, prices: PriceBook) -> Result {
        dispatchPrecondition(condition: .onQueue(queue))
        self.prices = prices
        if reset { scanner.reset() }
        if full || scanner.lastScan == nil {
            scanner.scanAll()
            return result(fullScan: true)
        }
        return result(fullScan: false)
    }

    /// Must be called on `queue`.
    func scanNow(paths: [String]) -> Result {
        dispatchPrecondition(condition: .onQueue(queue))
        if scanner.lastScan == nil { scanner.scanAll() } else { scanner.scan(paths: paths) }
        return result(fullScan: false)
    }

    private func result(fullScan: Bool) -> Result {
        let codexExists = scanner.folders.first { $0.url == scanner.codexRoot }?.exists ?? false
        let report = UsageReport.build(
            entries: scanner.ledger.entries, prices: prices, projectNames: scanner.projectNames,
            codexSessions: scanner.codexSessions, codexFolderExists: codexExists
        )
        return Result(report: report, folders: scanner.folders, entryCount: scanner.ledger.count,
                      fullScanDuration: fullScan ? scanner.lastScanDuration : nil)
    }
}

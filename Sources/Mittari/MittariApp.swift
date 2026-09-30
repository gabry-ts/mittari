import MittariCore
import PartitiUI
import SwiftUI

@main
struct MittariApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-snapshots"), args.indices.contains(i + 1) {
            exit(MainActor.assumeIsolated { Snapshots.render(to: URL(fileURLWithPath: args[i + 1])) })
        }
        if let i = args.firstIndex(of: "--render-icon"), args.indices.contains(i + 1) {
            exit(MainActor.assumeIsolated { Snapshots.renderIconSet(to: URL(fileURLWithPath: args[i + 1])) })
        }
        if args.contains("--summary") {
            exit(Summary.print())
        }
    }

    /// The menu bar item is an NSStatusItem owned by the app delegate; this scene only
    /// satisfies SwiftUI's need for one.
    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = SettingsStore()
    let monitor = UsageMonitor()
    private let notifier = Notifier()
    private let navigation = Navigation()
    private var window: NSWindow?
    private var statusItem: StatusItemController?
    private var observedInterval: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isFirstLaunch = !SettingsStore.hasSavedSettings
        store.saveNow()
        _ = Updater.controller

        statusItem = StatusItemController { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                MenuContent(
                    openStatistics: { [weak self] in
                        self?.statusItem?.closePopover()
                        self?.openStatisticsWindow()
                    },
                    openSettings: { [weak self] in
                        self?.statusItem?.closePopover()
                        self?.openSettingsWindow()
                    }
                )
                .environment(store)
                .environment(monitor)
            )
        } render: { [store, monitor] in
            StatusImage.parts(store: store, monitor: monitor)
        }

        monitor.onUpdate = { [weak self] in self?.checkThresholds() }
        monitor.prices = store.settings.prices
        observedInterval = store.settings.refreshInterval
        monitor.start(interval: observedInterval)
        observeSettings()

        if isFirstLaunch {
            LoginItem.register()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        store.saveNow()
    }

    /// Reopening the app (Spotlight, Finder) brings settings back, even with the menu bar
    /// icon hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }

    /// Pushes setting changes that affect scanning to the monitor as they happen.
    private func observeSettings() {
        let settings = withObservationTracking {
            store.settings
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettings() }
        }
        monitor.prices = settings.prices
        if settings.refreshInterval != observedInterval {
            observedInterval = settings.refreshInterval
            monitor.schedule(interval: observedInterval)
        }
        checkThresholds()
    }

    private func checkThresholds() {
        let limits = store.settings.limits
        notifier.check(gauge: Gauge(report: monitor.report, limits: limits, now: Date()), limits: limits)
    }

    func openSettingsWindow() {
        openWindow(.general)
    }

    func openStatisticsWindow() {
        openWindow(.statistics)
    }

    /// Opens the main window on `pane`, reusing it if it's already open.
    private func openWindow(_ pane: SettingsView.Pane) {
        NSApp.activate()
        navigation.pane = pane
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(navigation: navigation)
            .environment(store)
            .environment(monitor)
        let window = makeWindow(view, size: PUI.Window.dashboard, minSize: PUI.Window.dashboardMin)
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    /// A full-size content view under a clear title bar, so Partiti UI's floating sidebar
    /// runs under the traffic lights and each pane carries its own header.
    private func makeWindow(_ view: some View, size: NSSize, minSize: NSSize) -> NSWindow {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Mittari"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(size)
        window.minSize = minSize
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    /// A closed window is torn down rather than kept around, so its charts stop drawing
    /// in the background.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.contentViewController = nil
        if window === self.window { self.window = nil }
    }
}

/// `Mittari --summary` prints what the core reads from this Mac's logs, for checking the
/// numbers without the UI.
enum Summary {
    static func print() -> Int32 {
        setvbuf(stdout, nil, _IONBF, 0)
        let scanner = UsageScanner.standard()
        scanner.scanAll()
        let buildStart = Date()
        let entries = scanner.ledger.entries
        let sortTime = Date().timeIntervalSince(buildStart)
        let report = UsageReport.build(
            entries: entries, prices: .defaults, projectNames: scanner.projectNames,
            codexSessions: scanner.codexSessions,
            codexFolderExists: scanner.folders.first { $0.url == scanner.codexRoot }?.exists ?? false
        )
        let buildTime = Date().timeIntervalSince(buildStart)
        let gauge = Gauge(report: report, limits: LimitSettings(), now: Date())
        var lines: [String] = []
        for folder in scanner.folders {
            lines.append("folder \(folder.url.path): \(folder.exists ? "\(folder.fileCount) files" : "not found")")
        }
        lines.append(String(format: "full scan: %.2f s, %d messages after dedup (last %d days)",
                            scanner.lastScanDuration, scanner.ledger.count, Int(scanner.lookback / 86_400)))
        lines.append(String(format: "report build: %.0f ms (sorting entries %.0f ms)", buildTime * 1000, sortTime * 1000))
        lines.append("projects: \(Set(report.entries.map(\.project)).count)")
        lines.append("today: \(Format.tokens(report.today.tokens.total)) tokens (\(report.today.tokens.total)), \(Format.cost(report.today.cost))\(report.today.costIsPartial ? " + unpriced" : "")")
        lines.append("week: \(Format.tokens(report.week.tokens.total)) tokens, \(Format.cost(report.week.cost))")
        lines.append("month: \(Format.tokens(report.month.tokens.total)) tokens, \(Format.cost(report.month.cost))")
        if let block = gauge.block {
            lines.append("current block: \(block.start.formatted()) to \(block.end.formatted()), \(Format.tokens(block.tokens.total)) tokens, \(Format.cost(block.cost)), \(Gauge.percentText(gauge.fiveHourPercent)) est., resets in \(Format.duration(block.end.timeIntervalSinceNow))")
        } else {
            lines.append("current block: none")
        }
        lines.append("busiest block (30 days): \(Format.tokens(report.busiestBlockTokens)), busiest week: \(Format.tokens(report.busiestWeekTokens)), week \(Gauge.percentText(gauge.weekPercent))")
        lines.append("models (7 days): " + report.modelsWeek.map { "\($0.name) \(Format.tokens($0.totals.tokens.total)) \(Format.cost($0.totals.cost))" }.joined(separator: ", "))
        lines.append("projects today: " + report.projectsToday.prefix(5).map { "\($0.name) \(Format.tokens($0.totals.tokens.total))" }.joined(separator: ", "))
        lines.append("unpriced models: \(report.unpricedModels)")
        let codex = report.codex
        lines.append("codex: folder \(codex.folderExists), \(codex.sessionCount) recent sessions, \(codex.sessionsToday) today, token data: \(codex.tokensToday != nil), rate limits: \(codex.rateLimits != nil)")
        Swift.print(lines.joined(separator: "\n"))
        return 0
    }
}

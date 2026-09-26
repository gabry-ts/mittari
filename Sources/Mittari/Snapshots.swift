import AppKit
import MittariCore
import SwiftUI

/// `Mittari --render-snapshots <dir>` renders the popover, statistics and every
/// settings pane with sample data, in light and dark mode, for review and the README.
/// `Mittari --render-icon <dir>` writes AppIcon.iconset and AppIcon.icns.
/// Never reads the real logs or touches the real settings.json.
@MainActor
enum Snapshots {
    static func render(to dir: URL) -> Int32 {
        setvbuf(stdout, nil, _IONBF, 0)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let now = Date()
        let store = SettingsStore(settings: Settings())
        let monitor = SampleData.monitor(now: now)
        let empty = UsageMonitor(report: UsageReport(generatedAt: now), folders: SampleData.folders(empty: true), entryCount: 0, now: now)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            snapFitting(MenuContent(openStatistics: {}, openSettings: {}).environment(store).environment(monitor),
                        name: "popover-\(suffix)", dark: dark, dir: dir)
            snapWindow(SettingsView(navigation: Navigation(pane: .statistics)).environment(store).environment(monitor),
                       name: "statistics-\(suffix)", size: NSSize(width: 1080, height: 980), dark: dark, dir: dir)
            for pane in SettingsView.Pane.allCases where pane != .statistics {
                snapWindow(SettingsView(navigation: Navigation(pane: pane), expandedModels: ["claude-opus-5"]).environment(store).environment(monitor),
                           name: "settings-\(pane.rawValue)-\(suffix)", size: NSSize(width: 1080, height: 700), dark: dark, dir: dir,
                           growToContent: true)
            }
        }
        snapWindow(StatisticsView(range: .day).environment(store).environment(monitor),
                   name: "statistics-day-light", size: NSSize(width: 860, height: 980), dark: false, dir: dir)
        snapWindow(StatisticsView(range: .year).environment(store).environment(monitor),
                   name: "statistics-year-light", size: NSSize(width: 860, height: 980), dark: false, dir: dir)
        snapWindow(StatisticsView(range: .month).environment(store).environment(monitor),
                   name: "statistics-month-dark", size: NSSize(width: 860, height: 980), dark: true, dir: dir)
        snapFitting(MenuContent(openStatistics: {}, openSettings: {}).environment(store).environment(empty),
                    name: "popover-empty-light", dark: false, dir: dir)

        // Warning level and the status item on both menu bar appearances.
        var warning = Settings()
        warning.limits.mode = .custom
        warning.limits.fiveHourTokens = Int(Double(monitor.report.currentBlock?.tokens.total ?? 1) / 0.82)
        warning.menuBar.items = [.gauge, .percent, .weekGauge, .weekPercent, .resetTime, .costToday]
        let warningStore = SettingsStore(settings: warning)
        snapFitting(MenuContent(openStatistics: {}, openSettings: {}).environment(warningStore).environment(monitor),
                    name: "popover-warning-dark", dark: true, dir: dir)
        renderStatusItems([store, warningStore], monitor: monitor, to: dir.appendingPathComponent("menubar.png"))

        writePNG(renderIcon(size: 1024), to: dir.appendingPathComponent("icon-1024.png"))
        writePNG(renderIcon(size: 32), to: dir.appendingPathComponent("icon-32.png"))
        print("Snapshots written to \(dir.path)")
        return 0
    }

    // MARK: Icon

    static func renderIcon(size: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: AppIconView().frame(width: size, height: size))
        renderer.scale = 1
        return renderer.cgImage
    }

    static func renderIconSet(to dir: URL) -> Int32 {
        let iconset = dir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            writePNG(renderIcon(size: CGFloat(base)), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
            writePNG(renderIcon(size: CGFloat(base * 2)), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
        try? p.run()
        p.waitUntilExit()
        print(p.terminationStatus == 0 ? "Wrote \(dir.appendingPathComponent("AppIcon.icns").path)" : "iconutil failed")
        return p.terminationStatus
    }

    private static func writePNG(_ image: CGImage?, to url: URL) {
        guard let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    /// Status items drawn on a light and a dark menu bar strip.
    private static func renderStatusItems(_ stores: [SettingsStore], monitor: UsageMonitor, to url: URL) {
        let scale: CGFloat = 3
        let rows = stores.flatMap { store in [(store, false), (store, true)] }
        let width: CGFloat = 420
        let rowHeight: CGFloat = 26
        let image = NSImage(size: NSSize(width: width, height: rowHeight * CGFloat(rows.count)), flipped: true) { _ in
            for (index, row) in rows.enumerated() {
                let y = CGFloat(index) * rowHeight
                (row.1 ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(x: 0, y: y, width: width, height: rowHeight).fill()
                let item = StatusImage.render(StatusImage.parts(store: row.0, monitor: monitor), textColor: row.1 ? .white : .black)
                item.draw(in: NSRect(x: width - item.size.width - 12, y: y + (rowHeight - item.size.height) / 2,
                                     width: item.size.width, height: item.size.height))
            }
            return true
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("  menubar.png")
    }

    // MARK: Rendering

    /// Renders a view on a borderless window sized to fit its content, like the popover.
    private static func snapFitting(_ view: some View, name: String, dark: Bool, dir: URL) {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(controller.view.fittingSize)
        capture(window, name: name, dir: dir)
    }

    private static func snapWindow(_ view: some View, name: String, size: NSSize, dark: Bool, dir: URL, growToContent: Bool = false) {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        if growToContent {
            // Forms are List-backed, so grow the window to the tallest scroll view's
            // document height and long panes aren't cropped.
            window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let height = tallestDocumentHeight(in: controller.view)
            if height > size.height - 40 {
                window.setContentSize(NSSize(width: size.width, height: min(height + 40, 1400)))
            }
        }
        capture(window, name: name, dir: dir)
    }

    private static func capture(_ window: NSWindow, name: String, dir: URL) {
        // Off the visible displays, so nothing flashes on screen; the window server can
        // still composite and capture a window regardless of where it's positioned.
        window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        if let image = windowImage(window), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: dir.appendingPathComponent("\(name).png"))
            print("  \(name).png")
        }
        window.orderOut(nil)
        window.close()
    }

    private static func tallestDocumentHeight(in view: NSView) -> CGFloat {
        var tallest: CGFloat = 0
        if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
            tallest = document.frame.height
        }
        for subview in view.subviews {
            tallest = max(tallest, tallestDocumentHeight(in: subview))
        }
        return tallest
    }

    /// Captures one of our own windows through the window server, so AppKit-backed
    /// SwiftUI controls render exactly as on screen. Looked up at runtime because the
    /// symbol is no longer exposed in the SDK; capturing your own windows needs no permission.
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        // kCGWindowListOptionIncludingWindow = 8, boundsIgnoreFraming = 1, bestResolution = 8
        return fn(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue()
    }
}

/// A plausible month of Claude Code and Codex use, generated deterministically.
@MainActor
private enum SampleData {
    static func monitor(now: Date) -> UsageMonitor {
        let entries = claudeEntries(now: now)
        let projects = ["mittari", "tuuli", "kaiku", "partiti.app.mac", "notes-api", "dotfiles"]
        var names: [String: String] = [:]
        for name in projects { names[ProjectName.encode("/Users/me/code/\(name)")] = name }
        let report = UsageReport.build(entries: entries, prices: .defaults, projectNames: names,
                                       codexSessions: codexSessions(now: now), codexFolderExists: true, now: now)
        return UsageMonitor(report: report, folders: folders(empty: false), entryCount: entries.count, now: now)
    }

    static func folders(empty: Bool) -> [UsageScanner.Folder] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            .init(url: home.appendingPathComponent(".config/claude/projects"), exists: false, fileCount: 0),
            .init(url: home.appendingPathComponent(".claude/projects"), exists: !empty, fileCount: empty ? 0 : 812),
            .init(url: home.appendingPathComponent(".codex/sessions"), exists: !empty, fileCount: empty ? 0 : 37),
        ]
    }

    private struct Generator {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private static func claudeEntries(now: Date) -> [UsageEntry] {
        var random = Generator(state: 42)
        let projects = ["mittari", "tuuli", "kaiku", "partiti.app.mac", "notes-api", "dotfiles"]
        let weights = [0.34, 0.2, 0.16, 0.14, 0.1, 0.06]
        let calendar = Calendar.current
        var entries: [UsageEntry] = []
        let today = calendar.startOfDay(for: now)

        func pick() -> String {
            var roll = random.next()
            for (project, weight) in zip(projects, weights) {
                roll -= weight
                if roll < 0 { return project }
            }
            return projects[0]
        }

        func session(start: Date, minutes: Double, intensity: Double, project: String) {
            let sessionID = UUID().uuidString
            var t = start
            let end = start.addingTimeInterval(minutes * 60)
            while t < min(end, now) {
                let roll = random.next()
                let model = roll < 0.62 ? "claude-opus-5" : (roll < 0.9 ? "claude-sonnet-5" : "claude-haiku-4-5-20251001")
                let context = 40_000 + random.next() * 110_000 * intensity
                let tokens = TokenCounts(
                    input: Int(2 + random.next() * 40),
                    output: Int(150 + random.next() * 1_600 * intensity),
                    cacheWrite5m: 0,
                    cacheWrite1h: Int(random.next() * 9_000),
                    cacheRead: Int(context)
                )
                entries.append(UsageEntry(date: t, model: model, tokens: tokens,
                                          project: ProjectName.encode("/Users/me/code/\(project)"), session: sessionID))
                t = t.addingTimeInterval(20 + random.next() * 70)
            }
        }

        for dayOffset in (0..<31).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let weekend = weekday == 1 || weekday == 7
            let sessions = weekend ? Int(random.next() * 2) : 2 + Int(random.next() * 3)
            for _ in 0..<sessions {
                let hour = 9 + random.next() * 11
                let start = day.addingTimeInterval(hour * 3600)
                guard start < now.addingTimeInterval(-3 * 3600) || dayOffset > 0 else { continue }
                session(start: start, minutes: 20 + random.next() * 100, intensity: 0.5 + random.next(), project: pick())
            }
        }
        // A window in progress: started about two and a half hours ago.
        session(start: now.addingTimeInterval(-2.6 * 3600), minutes: 70, intensity: 1.1, project: "mittari")
        session(start: now.addingTimeInterval(-1.1 * 3600), minutes: 60, intensity: 1.0, project: "tuuli")
        session(start: now.addingTimeInterval(-0.5 * 3600), minutes: 40, intensity: 0.9, project: "kaiku")
        return entries
    }

    private static func codexSessions(now: Date) -> [CodexSession] {
        func stamp(_ date: Date) -> String { date.formatted(.iso8601) }
        var sessions: [CodexSession] = []
        for (index, (startHoursAgo, minutes, tokens)) in [(5.5, 42.0, 180_000), (1.4, 55.0, 260_000)].enumerated() {
            let start = now.addingTimeInterval(-startHoursAgo * 3600)
            let end = start.addingTimeInterval(minutes * 60)
            var parser = CodexLogParser(fileName: "rollout-sample-\(index).jsonl")
            parser.consume(Data(#"{"timestamp":"\#(stamp(start))","type":"session_meta","payload":{"id":"sample-\#(index)","cwd":"/Users/me/code/notes-api"}}"#.utf8))
            parser.consume(Data(#"{"timestamp":"\#(stamp(end))","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\#(tokens)}},"rate_limits":{"primary":{"used_percent":\#(index == 1 ? 38 : 12),"window_minutes":300,"resets_in_seconds":7200},"secondary":{"used_percent":21,"window_minutes":10080}}}}"#.utf8))
            sessions.append(parser.session)
        }
        return sessions
    }
}

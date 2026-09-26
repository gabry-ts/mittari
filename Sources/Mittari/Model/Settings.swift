import Foundation
import MittariCore

/// One piece of the status item, shown left to right in list order.
enum StatusElement: String, Codable, CaseIterable, Hashable {
    case gauge
    case percent
    case weekGauge
    case weekPercent
    case resetTime
    case tokensToday
    case costToday

    var title: String {
        switch self {
        case .gauge: "5-hour ring"
        case .percent: "5-hour %"
        case .weekGauge: "Weekly ring"
        case .weekPercent: "Weekly %"
        case .resetTime: "Time to reset"
        case .tokensToday: "Tokens today"
        case .costToday: "Cost today"
        }
    }

    var icon: String {
        switch self {
        case .gauge: "gauge.with.dots.needle.33percent"
        case .percent: "percent"
        case .weekGauge: "circle.dashed"
        case .weekPercent: "calendar"
        case .resetTime: "timer"
        case .tokensToday: "number"
        case .costToday: "dollarsign"
        }
    }
}

struct MenuBarSettings: Codable, Hashable {
    var items: [StatusElement] = [.gauge, .percent, .resetTime]

    /// What the status item actually shows: an empty list falls back to the gauge.
    var displayedItems: [StatusElement] { items.isEmpty ? [.gauge] : items }
}

enum PopoverSection: String, Codable, CaseIterable {
    case fiveHour
    case week
    case periods
    case models
    case projects
    case codex

    var title: String {
        switch self {
        case .fiveHour: "5-hour window"
        case .week: "Week"
        case .periods: "Today and this month"
        case .models: "Models"
        case .projects: "Projects today"
        case .codex: "Codex"
        }
    }

    var icon: String {
        switch self {
        case .fiveHour: "timer"
        case .week: "calendar"
        case .periods: "sum"
        case .models: "cpu"
        case .projects: "folder"
        case .codex: "terminal"
        }
    }
}

struct PopoverEntry: Codable, Hashable {
    var section: PopoverSection
    var isEnabled = true
}

/// What the menu bar popover shows, top to bottom in `sections` order.
struct PopoverSettings: Codable, Hashable {
    var sections = PopoverSection.allCases.map { PopoverEntry(section: $0) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try c.decodeIfPresent([PopoverEntry].self, forKey: .sections) ?? []
        // Sections added in later versions are appended, enabled.
        let missing = PopoverSection.allCases.filter { section in !saved.contains { $0.section == section } }
        sections = saved + missing.map { PopoverEntry(section: $0) }
    }
}

enum LimitMode: String, Codable, CaseIterable {
    /// 100% is the busiest window seen recently.
    case auto
    /// 100% is a token budget the user sets.
    case custom

    var title: String {
        switch self {
        case .auto: "Auto"
        case .custom: "Custom budgets"
        }
    }
}

struct LimitSettings: Codable, Hashable {
    var mode = LimitMode.auto
    var fiveHourTokens = 100_000_000
    var weeklyTokens = 2_000_000_000
    var warningPercent = 75.0
    var criticalPercent = 90.0
    var notify = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LimitSettings()
        mode = try c.decodeIfPresent(LimitMode.self, forKey: .mode) ?? d.mode
        fiveHourTokens = try c.decodeIfPresent(Int.self, forKey: .fiveHourTokens) ?? d.fiveHourTokens
        weeklyTokens = try c.decodeIfPresent(Int.self, forKey: .weeklyTokens) ?? d.weeklyTokens
        warningPercent = try c.decodeIfPresent(Double.self, forKey: .warningPercent) ?? d.warningPercent
        criticalPercent = try c.decodeIfPresent(Double.self, forKey: .criticalPercent) ?? d.criticalPercent
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify
    }
}

struct Settings: Codable, Hashable {
    /// Seconds between full rescans; file changes are picked up sooner by the watcher.
    var refreshInterval: Double = 60
    var menuBar = MenuBarSettings()
    var popover = PopoverSettings()
    var limits = LimitSettings()
    var prices = PriceBook.defaults

    init() {}

    /// Missing keys fall back to defaults, so settings files from older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        refreshInterval = try c.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? d.refreshInterval
        menuBar = try c.decodeIfPresent(MenuBarSettings.self, forKey: .menuBar) ?? d.menuBar
        popover = try c.decodeIfPresent(PopoverSettings.self, forKey: .popover) ?? d.popover
        limits = try c.decodeIfPresent(LimitSettings.self, forKey: .limits) ?? d.limits
        prices = try c.decodeIfPresent(PriceBook.self, forKey: .prices) ?? d.prices
    }
}

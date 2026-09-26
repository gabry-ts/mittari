import Foundation
import MittariCore

/// How close the current 5-hour window and the week are to 100%, under the chosen
/// limit mode. Always an estimate: real plan limits aren't in the logs.
struct Gauge: Equatable {
    enum Level: Int, Comparable {
        case normal
        case warning
        case critical

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The window containing now, if a message opened one.
    var block: UsageBlock?
    /// 0...100+, nil when there is nothing to compare against yet.
    var fiveHourPercent: Double?
    var weekPercent: Double?
    var fiveHourLimit: Int
    var weekLimit: Int
    var level = Level.normal

    init(report: UsageReport, limits: LimitSettings, now: Date) {
        block = report.currentBlock.flatMap { $0.contains(now) ? $0 : nil }
        switch limits.mode {
        case .auto:
            fiveHourLimit = report.busiestBlockTokens
            weekLimit = report.busiestWeekTokens
        case .custom:
            fiveHourLimit = limits.fiveHourTokens
            weekLimit = limits.weeklyTokens
        }
        if fiveHourLimit > 0 {
            fiveHourPercent = Double(block?.tokens.total ?? 0) / Double(fiveHourLimit) * 100
        }
        if weekLimit > 0 {
            weekPercent = Double(report.week.tokens.total) / Double(weekLimit) * 100
        }
        level = Self.level(fiveHourPercent, limits: limits)
    }

    static func level(_ percent: Double?, limits: LimitSettings) -> Level {
        guard let percent else { return .normal }
        if percent >= limits.criticalPercent { return .critical }
        if percent >= limits.warningPercent { return .warning }
        return .normal
    }

    func timeToReset(now: Date) -> TimeInterval? {
        block.map { max($0.end.timeIntervalSince(now), 0) }
    }

    static func percentText(_ percent: Double?) -> String {
        guard let percent else { return "–%" }
        return "\(Int(percent.rounded()))%"
    }
}

extension LimitMode {
    /// What 100% means, for labels and tooltips.
    var explanation: String {
        switch self {
        case .auto: "100% is your busiest earlier 5-hour window (and week) in the last 30 days, so a new record reads above 100%. Plan limits aren't in the logs: this is an estimate."
        case .custom: "100% is your own token budget. Plan limits aren't in the logs: this is an estimate."
        }
    }
}

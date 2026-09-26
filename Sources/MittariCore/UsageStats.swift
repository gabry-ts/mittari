import Foundation

/// Numbers for the Statistics window over one range.
public struct UsageStats: Sendable {
    public enum Range: String, CaseIterable, Sendable {
        case day, week, month

        public var title: String {
            switch self {
            case .day: "24 Hours"
            case .week: "7 Days"
            case .month: "30 Days"
            }
        }

        public var duration: TimeInterval {
            switch self {
            case .day: 86_400
            case .week: 7 * 86_400
            case .month: 30 * 86_400
            }
        }

        /// Bars are hours for the shorter ranges and days for 30 days.
        public var bucket: Calendar.Component { self == .month ? .day : .hour }
    }

    public struct Bucket: Hashable, Sendable, Identifiable {
        public var start: Date
        public var tokens = 0
        public var cost = 0.0
        public var id: Date { start }
    }

    public struct Session: Hashable, Sendable {
        public var project: String
        public var start: Date
        public var end: Date
        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    public var range: Range
    public var interval: DateInterval
    public var totals = Totals()
    public var buckets: [Bucket] = []
    public var blocks: [UsageBlock] = []
    public var byProject: [Slice] = []
    public var byModel: [Slice] = []
    /// The busiest single hour.
    public var peakHour: Bucket?
    public var longestSession: Session?

    public init(report: UsageReport, range: Range, now: Date = Date(), calendar: Calendar = .current) {
        self.range = range
        let unit = range.bucket
        let end = calendar.dateInterval(of: unit, for: now)?.end ?? now
        let count = range == .month ? 30 : Int(range.duration / 3600)
        let start = calendar.date(byAdding: unit, value: -count, to: end) ?? now.addingTimeInterval(-range.duration)
        interval = DateInterval(start: start, end: end)

        var buckets: [Date: Bucket] = [:]
        var hours: [Date: Bucket] = [:]
        var projects: [String: Slice] = [:]
        var models: [String: Slice] = [:]
        var sessions: [String: Session] = [:]
        for entry in report.entries where interval.contains(entry.date) {
            totals.add(entry)
            let key = calendar.dateInterval(of: unit, for: entry.date)?.start ?? entry.date
            buckets[key, default: Bucket(start: key)].tokens += entry.tokens.total
            buckets[key]?.cost += entry.cost ?? 0
            let hour = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
            hours[hour, default: Bucket(start: hour)].tokens += entry.tokens.total
            hours[hour]?.cost += entry.cost ?? 0
            projects[entry.project, default: Slice(id: entry.project, name: report.projectName(entry.project))].totals.add(entry)
            let model = ModelName.normalize(entry.model)
            models[model, default: Slice(id: model, name: ModelName.display(model))].totals.add(entry)
            if !entry.session.isEmpty {
                if var session = sessions[entry.session] {
                    session.start = min(session.start, entry.date)
                    session.end = max(session.end, entry.date)
                    sessions[entry.session] = session
                } else {
                    sessions[entry.session] = Session(project: entry.project, start: entry.date, end: entry.date)
                }
            }
        }

        // Every slot in the range, empty ones included, so the chart has a steady axis.
        var slots: [Bucket] = []
        var cursor = start
        while cursor < end {
            slots.append(buckets[cursor] ?? Bucket(start: cursor))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.buckets = slots
        blocks = report.blocks.filter { $0.end > interval.start && $0.start < interval.end }
        byProject = projects.values.sorted { $0.totals.tokens.total > $1.totals.tokens.total }
        byModel = models.values.sorted { $0.totals.tokens.total > $1.totals.tokens.total }
        peakHour = hours.values.max { $0.tokens < $1.tokens }
        longestSession = sessions.values.max { $0.duration < $1.duration }
    }
}

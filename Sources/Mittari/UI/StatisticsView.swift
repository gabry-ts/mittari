import Charts
import MittariCore
import SwiftUI

/// Claude Code usage over 24 hours, 7 days or 30 days, from the local transcripts.
struct StatisticsView: View {
    @Environment(UsageMonitor.self) private var monitor
    @State private var range: UsageStats.Range

    init(range: UsageStats.Range = .week) {
        _range = State(initialValue: range)
    }

    var body: some View {
        let stats = UsageStats(report: monitor.report, range: range, now: monitor.now)
        AirPage(title: "Statistics", subtitle: "Claude Code usage from your local transcripts. Costs are API list-price equivalents.") {
            Picker("Range", selection: $range) {
                ForEach(UsageStats.Range.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Card(padding: 18) {
                HStack(alignment: .top, spacing: 16) {
                    StatTile(title: "Tokens", value: Format.tokens(stats.totals.tokens.total),
                             detail: "\(Format.tokens(stats.totals.tokens.output)) output")
                    StatTile(title: "Cost", value: Format.cost(stats.totals.cost) + (stats.totals.costIsPartial ? "+" : ""),
                             detail: "API list-price equivalent")
                    StatTile(title: "Peak hour", value: stats.peakHour.map { Format.tokens($0.tokens) } ?? "–",
                             detail: stats.peakHour.map { $0.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()) })
                    StatTile(title: "Longest session", value: stats.longestSession.map { Format.duration($0.duration) } ?? "–",
                             detail: stats.longestSession.map { monitor.report.projectName($0.project) })
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CardTitle(title: range == .month ? "Tokens per day" : "Tokens per hour", systemImage: "chart.bar.xaxis")
                        Spacer()
                        if range != .month {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.amber.opacity(0.18))
                                    .frame(width: 14, height: 10)
                                Text("5-hour windows")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if stats.totals.isEmpty {
                        ContentUnavailableView("No usage in this range", systemImage: "chart.bar",
                                               description: Text("Claude Code activity shows up here as soon as it is logged."))
                            .frame(height: 220)
                    } else {
                        chart(stats)
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                breakdown("By project", systemImage: "folder", slices: stats.byProject, total: stats.totals.tokens.total)
                breakdown("By model", systemImage: "cpu", slices: stats.byModel, total: stats.totals.tokens.total)
            }
        }
        .frame(minWidth: 760, minHeight: 600)
    }

    private func chart(_ stats: UsageStats) -> some View {
        let unit: Calendar.Component = range == .month ? .day : .hour
        let shaded = range == .month ? [] : stats.blocks
        return Chart {
            ForEach(shaded) { block in
                RectangleMark(
                    xStart: .value("Start", max(block.start, stats.interval.start)),
                    xEnd: .value("End", min(block.end, stats.interval.end))
                )
                .foregroundStyle(Theme.amber.opacity(block.contains(monitor.now) ? 0.26 : 0.13))
            }
            ForEach(stats.buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Tokens", bucket.tokens))
                    .foregroundStyle(Theme.amber.gradient)
                    .cornerRadius(2)
            }
        }
        .chartXScale(domain: stats.interval.start...stats.interval.end)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tokens = value.as(Int.self) { Text(verbatim: Format.tokens(tokens)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .day ? 8 : 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 240)
    }

    private func breakdown(_ title: String, systemImage: String, slices: [Slice], total: Int) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(title: title, systemImage: systemImage)
                if slices.isEmpty {
                    Text("Nothing in this range")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(slices.prefix(8).enumerated()), id: \.element.id) { index, slice in
                    SliceRow(name: slice.name, totals: slice.totals, share: Double(slice.totals.tokens.total) / Double(max(total, 1)),
                             color: systemImage == "cpu" ? Theme.palette[index % Theme.palette.count] : Theme.amber)
                }
                if slices.count > 8 {
                    Text("and \(slices.count - 8) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

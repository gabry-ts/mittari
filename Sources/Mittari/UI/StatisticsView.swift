import Charts
import MittariCore
import PartitiUI
import SwiftUI

/// Claude Code usage over 24 hours, 7 days or 30 days, from the local transcripts.
struct StatisticsView: View {
    @Environment(UsageMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    @State private var range: UsageStats.Range

    init(range: UsageStats.Range = .week) {
        _range = State(initialValue: range)
    }

    var body: some View {
        let stats = UsageStats(report: monitor.report, range: range, now: monitor.now)
        let ink = Ink(colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: PUI.Space.l) {
                PaneHeader(SettingsView.Pane.statistics.title, subtitle: "Claude Code usage from your local transcripts. Costs are API list-price equivalents.",
                           symbol: SettingsView.Pane.statistics.icon, color: SettingsView.Pane.statistics.tint)
                    .padding(.bottom, PUI.Space.xs)

                SegmentedPill(UsageStats.Range.allCases.map { (value: $0, title: $0.title) }, selection: $range,
                              height: PUI.Control.regular)

                Card(padding: PUI.Space.xl) {
                    HStack(alignment: .top, spacing: PUI.Space.xl) {
                        StatTile("Tokens", value: Format.tokens(stats.totals.tokens.total),
                                           detail: "\(Format.tokens(stats.totals.tokens.output)) output")
                        divider(ink)
                        StatTile("Cost", value: Format.costText(stats.totals), detail: "API list-price equivalent")
                        divider(ink)
                        StatTile(Text("Peak hour"), value: stats.peakHour.map { Format.tokens($0.tokens) } ?? "–",
                                           detail: stats.peakHour.map { Text(verbatim: $0.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())) })
                        divider(ink)
                        StatTile(Text("Longest session"), value: stats.longestSession.map { Format.duration($0.duration) } ?? "–",
                                           detail: stats.longestSession.map { Text(verbatim: monitor.report.projectName($0.project)) })
                    }
                }

                Card(padding: PUI.Space.xl) {
                    VStack(alignment: .leading, spacing: PUI.Space.l) {
                        SectionHeader("Tokens per \(unitName)") {
                            if range.bucket == .hour {
                                HStack(spacing: PUI.Space.xs + 1) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(MittariStyle.accent.color.opacity(0.18))
                                        .frame(width: 14, height: 10)
                                    Text("5-hour windows")
                                }
                            }
                        }
                        if stats.totals.isEmpty {
                            ContentUnavailableView("No usage in this range", systemImage: "chart.bar",
                                                   description: Text("Claude Code activity shows up here as soon as it is logged."))
                                .frame(height: 220)
                        } else {
                            chart(stats, ink: ink)
                        }
                    }
                }

                HStack(alignment: .top, spacing: PUI.Popover.cardGap) {
                    breakdown("By project", slices: stats.byProject, total: stats.totals.tokens.total, colored: false)
                    breakdown("By model", slices: stats.byModel, total: stats.totals.tokens.total, colored: true)
                }
            }
            .padding(.horizontal, PUI.Space.xxl)
            .padding(.top, PUI.Space.xxl + PUI.Space.xs)
            .padding(.bottom, PUI.Space.xxl)
            .frame(maxWidth: MittariStyle.dashboardMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func divider(_ ink: Ink) -> some View {
        Rectangle().fill(ink.hairline).frame(width: 0.5, height: 52)
    }

    private var unitName: String {
        switch range.bucket {
        case .hour: "hour"
        case .day: "day"
        default: "week"
        }
    }

    private func chart(_ stats: UsageStats, ink: Ink) -> some View {
        let unit = range.bucket
        // Windows only read at hourly resolution; on longer ranges they'd be a solid wash.
        let shaded = unit == .hour ? stats.blocks : []
        return Chart {
            ForEach(shaded) { block in
                RectangleMark(
                    xStart: .value("Start", max(block.start, stats.interval.start)),
                    xEnd: .value("End", min(block.end, stats.interval.end))
                )
                .foregroundStyle(MittariStyle.accent.color.opacity(block.contains(monitor.now) ? 0.26 : 0.13))
            }
            ForEach(stats.buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: unit), y: .value("Tokens", bucket.tokens))
                    .foregroundStyle(MittariStyle.accent.color.gradient)
                    .cornerRadius(2)
            }
        }
        .chartXScale(domain: stats.interval.start...stats.interval.end)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(ink.hairline)
                AxisValueLabel {
                    if let tokens = value.as(Int.self) { Text(verbatim: Format.tokens(tokens)) }
                }
                .font(PUI.Font.caption.monospacedDigit())
                .foregroundStyle(ink.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .day ? 8 : 7)) { _ in
                AxisGridLine().foregroundStyle(ink.hairline)
                AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
                    .font(PUI.Font.caption.monospacedDigit())
                    .foregroundStyle(ink.secondary)
            }
        }
        .frame(height: 240)
    }

    private func breakdown(_ title: LocalizedStringKey, slices: [Slice], total: Int, colored: Bool) -> some View {
        Card(padding: PUI.Space.xl) {
            VStack(alignment: .leading, spacing: PUI.Space.m) {
                SectionHeader(title)
                if slices.isEmpty {
                    Text("Nothing in this range")
                        .font(PUI.Font.callout)
                        .foregroundStyle(Ink(colorScheme).secondary)
                }
                ForEach(Array(slices.prefix(8).enumerated()), id: \.element.id) { index, slice in
                    SliceRow(name: slice.name, totals: slice.totals, share: Double(slice.totals.tokens.total) / Double(max(total, 1)),
                             color: colored ? MittariStyle.series[index % MittariStyle.series.count] : MittariStyle.accent.color)
                }
                if slices.count > 8 {
                    Text("and \(slices.count - 8) more")
                        .font(PUI.Font.caption)
                        .foregroundStyle(Ink(colorScheme).secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

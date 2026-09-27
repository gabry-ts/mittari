import MittariCore
import SwiftUI

/// The menu bar popover. Each section can be turned on, off and reordered in Settings.
struct MenuContent: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor
    let openStatistics: () -> Void
    let openSettings: () -> Void

    var body: some View {
        let report = monitor.report
        let gauge = Gauge(report: report, limits: store.settings.limits, now: monitor.now)
        VStack(alignment: .leading, spacing: 10) {
            header
            if report.hasClaudeData {
                ForEach(store.settings.popover.sections.filter(\.isEnabled), id: \.section) { entry in
                    sectionView(entry.section, report: report, gauge: gauge)
                }
            } else {
                Card(padding: 14) {
                    emptyClaude
                }
                if store.settings.popover.sections.contains(where: { $0.section == .codex && $0.isEnabled }) {
                    sectionView(.codex, report: report, gauge: gauge)
                }
            }
            footer
        }
        .padding(12)
        .frame(width: 320)
        .background(AirBackground())
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(Theme.amber.gradient)
            Text("Claude Code")
                .font(.system(.headline, design: .rounded))
            Spacer()
            let mode = store.settings.limits.mode
            Label(mode == .auto ? "Auto limit" : "Custom limit", systemImage: "info.circle")
                .labelStyle(TrailingIconLabelStyle())
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(mode.explanation)
        }
        .padding(.horizontal, 4)
    }

    private var emptyClaude: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No Claude Code usage yet", systemImage: "tray")
                .font(.callout.weight(.semibold))
            Text("Mittari reads the transcripts Claude Code keeps in ~/.claude/projects. They show up here as soon as you use it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button(action: openStatistics) {
                    Label("Statistics…", systemImage: "chart.bar.xaxis")
                }
                Button(action: openSettings) {
                    Label("Settings…", systemImage: "gearshape")
                }
                .keyboardShortcut(",")
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit", systemImage: "power")
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.callout)
            Divider()
            HStack(spacing: 14) {
                Button("Check for Updates…") { Updater.checkForUpdates() }
                Spacer()
                Button("Buy Me a Coffee…") { ExternalLinks.openBuyMeACoffee() }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func sectionView(_ section: PopoverSection, report: UsageReport, gauge: Gauge) -> some View {
        switch section {
        case .fiveHour:
            Card(padding: 12) { fiveHour(gauge) }
        case .week:
            Card(padding: 12) { week(report, gauge: gauge) }
        case .periods:
            Card(padding: 12) {
                HStack(alignment: .top) {
                    period("Today", report.today)
                    Divider().frame(height: 40)
                    period("This month", report.month)
                        .padding(.leading, 8)
                }
            }
        case .models:
            if !report.modelsWeek.isEmpty {
                Card(padding: 12) { models(report) }
            }
        case .projects:
            Card(padding: 12) { projects(report) }
        case .codex:
            Card(padding: 12) { codex(report.codex) }
        }
    }

    // MARK: Sections

    private func fiveHour(_ gauge: Gauge) -> some View {
        let color = Theme.color(gauge.level)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                caption("5-hour window")
                EstimateBadge(mode: store.settings.limits.mode)
                Spacer()
                if let block = gauge.block {
                    caption("resets \(block.end.clockText)")
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: Gauge.percentText(gauge.block == nil ? 0 : gauge.fiveHourPercent))
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(gauge.level == .normal ? AnyShapeStyle(.primary) : AnyShapeStyle(color))
                Spacer()
                if let remaining = gauge.timeToReset(now: monitor.now) {
                    Text("in \(Format.duration(remaining))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("No active window")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            UsageBar(percent: gauge.block == nil ? 0 : gauge.fiveHourPercent, color: color)
            if let block = gauge.block {
                HStack(spacing: 4) {
                    caption("\(Format.tokens(block.tokens.total)) of ~\(Format.tokens(gauge.fiveHourLimit)) tokens")
                    Spacer()
                    Text(verbatim: block.unpricedTokens > 0 && block.cost == 0 ? "—" : Format.cost(block.cost))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help("API list-price equivalent")
                }
            } else {
                caption("A new window opens with your next message.")
            }
        }
    }

    private func week(_ report: UsageReport, gauge: Gauge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                caption("Last 7 days")
                EstimateBadge(mode: store.settings.limits.mode)
                Spacer()
                Text(verbatim: Gauge.percentText(gauge.weekPercent))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            UsageBar(percent: gauge.weekPercent, color: Theme.color(Gauge.level(gauge.weekPercent, limits: store.settings.limits)))
            HStack {
                caption("\(Format.tokens(report.week.tokens.total)) tokens")
                Spacer()
                CostText(totals: report.week)
                    .font(.caption)
            }
        }
    }

    private func period(_ title: String, _ totals: Totals) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            caption(title)
            Text(verbatim: Format.tokens(totals.tokens.total))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 3) {
                CostText(totals: totals)
                Text("API equiv.")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func models(_ report: UsageReport) -> some View {
        let total = max(report.week.tokens.total, 1)
        return VStack(alignment: .leading, spacing: 8) {
            caption("Models, last 7 days")
            ForEach(Array(report.modelsWeek.prefix(4).enumerated()), id: \.element.id) { index, slice in
                SliceRow(name: slice.name, totals: slice.totals, share: Double(slice.totals.tokens.total) / Double(total),
                         color: Theme.palette[index % Theme.palette.count])
            }
        }
    }

    private func projects(_ report: UsageReport) -> some View {
        let slices = report.projectsToday
        let total = max(report.today.tokens.total, 1)
        return VStack(alignment: .leading, spacing: 8) {
            caption("Projects today")
            if slices.isEmpty {
                Text("Nothing yet today")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(slices.prefix(3)) { slice in
                SliceRow(name: slice.name, totals: slice.totals, share: Double(slice.totals.tokens.total) / Double(total))
            }
            if slices.count > 3 {
                let others = slices.dropFirst(3).reduce(into: Totals()) { sum, slice in
                    sum.tokens += slice.totals.tokens
                    sum.cost += slice.totals.cost
                    sum.unpricedTokens += slice.totals.unpricedTokens
                    sum.messages += slice.totals.messages
                }
                SliceRow(name: "Others (\(slices.count - 3))", totals: others,
                         share: Double(others.tokens.total) / Double(total), color: .secondary)
            }
        }
    }

    @ViewBuilder
    private func codex(_ codex: CodexSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                caption("Codex")
                Spacer()
                if let last = codex.lastActivity, codex.sessionsToday == 0 {
                    caption("last used \(last.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            if !codex.folderExists || codex.sessionCount == 0 && codex.lastActivity == nil {
                Text(codex.folderExists ? "No recent Codex sessions" : "Codex isn't set up on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top) {
                    miniStat("Sessions today", "\(codex.sessionsToday)")
                    miniStat("Active today", codex.activeToday > 0 ? Format.duration(codex.activeToday) : "–")
                    if let tokens = codex.tokensToday {
                        miniStat("Tokens today", Format.tokens(tokens))
                    }
                }
                if let limits = codex.rateLimits, let primary = limits.primary {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            caption("Codex 5-hour limit, as reported")
                            Spacer()
                            Text(verbatim: "\(Int(primary.usedPercent.rounded()))%")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        UsageBar(percent: primary.usedPercent, color: Theme.color(Gauge.level(primary.usedPercent, limits: store.settings.limits)), height: 4)
                        caption("as of \(limits.observedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
        }
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            caption(title)
            Text(verbatim: value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Text first, icon after.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon
        }
    }
}

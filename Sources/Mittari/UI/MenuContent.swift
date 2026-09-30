import MittariCore
import PartitiUI
import SwiftUI

/// The menu bar popover. Each section can be turned on, off and reordered in Settings.
struct MenuContent: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    let openStatistics: () -> Void
    let openSettings: () -> Void

    var body: some View {
        let report = monitor.report
        let gauge = Gauge(report: report, limits: store.settings.limits, now: monitor.now)
        PopoverScaffold {
            header
        } content: {
            if report.hasClaudeData {
                ForEach(store.settings.popover.sections.filter(\.isEnabled), id: \.section) { entry in
                    sectionView(entry.section, report: report, gauge: gauge)
                }
            } else {
                EmptyState(symbol: "tray", title: "No Claude Code usage yet",
                           message: "Mittari reads the transcripts Claude Code keeps in ~/.claude/projects. They show up here as soon as you use it.")
                if store.settings.popover.sections.contains(where: { $0.section == .codex && $0.isEnabled }) {
                    sectionView(.codex, report: report, gauge: gauge)
                }
            }
        } footer: {
            PopoverFooter(
                actions: [.init("Statistics…", symbol: "chart.bar.xaxis", perform: openStatistics)],
                onSettings: openSettings,
                onCheckForUpdates: { Updater.checkForUpdates() },
                onBuyMeACoffee: { ExternalLinks.openBuyMeACoffee() })
        }
        .puiAccent(MittariStyle.accent)
    }

    private var header: some View {
        let mode = store.settings.limits.mode
        return PopoverHeader(icon: AppIconView.image, name: MittariStyle.accent.name) {
            HeaderStatus(mode == .auto ? "Auto limit" : "Custom limit", symbol: "info.circle")
                .help(mode.explanation)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: PopoverSection, report: UsageReport, gauge: Gauge) -> some View {
        switch section {
        case .fiveHour:
            Card { fiveHour(gauge) }
        case .week:
            Card { week(report, gauge: gauge) }
        case .periods:
            Card {
                HStack(alignment: .top, spacing: PUI.Space.l) {
                    period("Today", report.today)
                    Rectangle().fill(ink.hairline).frame(width: 0.5, height: 52)
                    period("This month", report.month)
                }
            }
        case .models:
            if !report.modelsWeek.isEmpty {
                Card { models(report) }
            }
        case .projects:
            Card { projects(report) }
        case .codex:
            Card { codex(report.codex) }
        }
    }

    private var ink: Ink { Ink(colorScheme) }

    // MARK: Sections

    private func fiveHour(_ gauge: Gauge) -> some View {
        let color = MittariStyle.color(gauge.level)
        let percent = gauge.block == nil ? 0 : gauge.fiveHourPercent
        let ringSize: CGFloat = 76
        return HStack(spacing: PUI.Space.l) {
            GaugeRing(min(max((percent ?? 0) / 100, 0), 1), color: color, lineWidth: 7, size: ringSize) {
                VStack(spacing: 0) {
                    Text(verbatim: Gauge.percentText(percent))
                        .font(PUI.Font.stat)
                        .foregroundStyle(gauge.level == .normal ? ink.primary : PUI.legible(color, colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("5h")
                        .font(PUI.Font.caption)
                        .foregroundStyle(ink.secondary)
                }
                .padding(.horizontal, PUI.Space.s)
            }
            VStack(alignment: .leading, spacing: PUI.Space.xxs) {
                HStack(spacing: PUI.Space.s) {
                    label("5-hour window")
                    EstimateBadge(mode: store.settings.limits.mode)
                }
                if let block = gauge.block {
                    Text("in \(Format.duration(gauge.timeToReset(now: monitor.now) ?? 0))")
                        .font(PUI.Font.headline)
                        .monospacedDigit()
                        .foregroundStyle(ink.primary)
                        .padding(.top, PUI.Space.xxs)
                    caption("resets \(block.end.clockText)")
                    Spacer(minLength: PUI.Space.s)
                    HStack(spacing: PUI.Space.xs) {
                        caption("\(Format.tokens(block.tokens.total)) of ~\(Format.tokens(gauge.fiveHourLimit)) tokens")
                        Spacer(minLength: PUI.Space.xs)
                        Text(verbatim: block.unpricedTokens > 0 && block.cost == 0 ? "—" : Format.cost(block.cost))
                            .font(PUI.Font.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(ink.primary)
                            .help("API list-price equivalent")
                    }
                } else {
                    Text("No active window")
                        .font(PUI.Font.headline)
                        .foregroundStyle(ink.primary)
                        .padding(.top, PUI.Space.xxs)
                    Spacer(minLength: PUI.Space.s)
                    caption("A new window opens with your next message.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(height: ringSize)
        }
    }

    private func week(_ report: UsageReport, gauge: Gauge) -> some View {
        VStack(alignment: .leading, spacing: PUI.Space.s) {
            HStack(spacing: PUI.Space.s) {
                label("Last 7 days")
                EstimateBadge(mode: store.settings.limits.mode)
                Spacer()
                Text(verbatim: Gauge.percentText(gauge.weekPercent))
                    .font(PUI.Font.headline)
                    .monospacedDigit()
                    .foregroundStyle(ink.primary)
            }
            UsageMeter(percent: gauge.weekPercent, color: MittariStyle.color(Gauge.level(gauge.weekPercent, limits: store.settings.limits)))
            HStack {
                caption("\(Format.tokens(report.week.tokens.total)) tokens")
                Spacer()
                CostText(totals: report.week)
                    .font(PUI.Font.caption)
            }
        }
    }

    private func period(_ title: LocalizedStringKey, _ totals: Totals) -> some View {
        StatTile(Text(title), value: Format.tokens(totals.tokens.total),
                           detail: Text("\(Format.costText(totals)) API equiv."))
            .help(totals.costIsPartial ? "Some usage has no price and is left out. Set prices in Settings." : "API list-price equivalent")
    }

    private func models(_ report: UsageReport) -> some View {
        let total = max(report.week.tokens.total, 1)
        return VStack(alignment: .leading, spacing: PUI.Space.s) {
            SectionHeader("Models, last 7 days")
            ForEach(Array(report.modelsWeek.prefix(4).enumerated()), id: \.element.id) { index, slice in
                SliceRow(name: slice.name, totals: slice.totals, share: Double(slice.totals.tokens.total) / Double(total),
                         color: MittariStyle.series[index % MittariStyle.series.count])
            }
        }
    }

    private func projects(_ report: UsageReport) -> some View {
        let slices = report.projectsToday
        let total = max(report.today.tokens.total, 1)
        return VStack(alignment: .leading, spacing: PUI.Space.s) {
            SectionHeader("Projects today")
            if slices.isEmpty {
                Text("Nothing yet today")
                    .font(PUI.Font.callout)
                    .foregroundStyle(ink.secondary)
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
                         share: Double(others.tokens.total) / Double(total), color: ink.tertiary, isSummary: true)
            }
        }
    }

    @ViewBuilder
    private func codex(_ codex: CodexSummary) -> some View {
        VStack(alignment: .leading, spacing: PUI.Space.s) {
            SectionHeader("Codex") {
                if let last = codex.lastActivity, codex.sessionsToday == 0 {
                    Text("last used \(last.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            if !codex.folderExists || codex.sessionCount == 0 && codex.lastActivity == nil {
                Text(codex.folderExists ? "No recent Codex sessions" : "Codex isn't set up on this Mac")
                    .font(PUI.Font.callout)
                    .foregroundStyle(ink.secondary)
            } else {
                HStack(alignment: .top) {
                    miniStat("Sessions today", "\(codex.sessionsToday)")
                    miniStat("Active today", codex.activeToday > 0 ? Format.duration(codex.activeToday) : "–")
                    if let tokens = codex.tokensToday {
                        miniStat("Tokens today", Format.tokens(tokens))
                    }
                }
                if let limits = codex.rateLimits, let primary = limits.primary {
                    VStack(alignment: .leading, spacing: PUI.Space.xs) {
                        HStack {
                            caption("Codex 5-hour limit, as reported")
                            Spacer()
                            Text(verbatim: "\(Int(primary.usedPercent.rounded()))%")
                                .font(PUI.Font.label)
                                .monospacedDigit()
                                .foregroundStyle(ink.primary)
                        }
                        UsageMeter(percent: primary.usedPercent,
                                   color: MittariStyle.color(Gauge.level(primary.usedPercent, limits: store.settings.limits)), height: 4)
                        caption("as of \(limits.observedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
        }
    }

    private func miniStat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: PUI.Space.xxs) {
            label(title)
            Text(verbatim: value)
                .font(PUI.Font.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(ink.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(PUI.Font.label)
            .foregroundStyle(ink.secondary)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(PUI.Font.caption)
            .monospacedDigit()
            .foregroundStyle(ink.secondary)
    }
}

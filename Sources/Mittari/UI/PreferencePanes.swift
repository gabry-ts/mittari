import MittariCore
import PartitiUI
import SwiftUI

struct GeneralView: View {
    @Environment(SettingsStore.self) private var store
    @State private var launchAtLogin = LoginItem.status == .enabled

    var body: some View {
        @Bindable var store = store
        MittariPane(pane: .general, subtitle: "Startup and how often the logs are read again.") {
            SettingsGroup("Startup") {
                SwitchRow("Launch at login", isOn: $launchAtLogin)
                if LoginItem.status == .requiresApproval {
                    SettingsRow("Waiting for your approval in System Settings") {
                        Button("Approve in System Settings…") { LoginItem.openSystemSettings() }
                            .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                    }
                }
            }
            .onChange(of: launchAtLogin) { _, enabled in
                enabled ? LoginItem.register() : LoginItem.unregister()
            }
            SettingsGroup("Refresh", footer: "New lines in the logs are picked up within a few seconds of being written. The periodic rescan is a fallback, and only reads what changed.") {
                SettingsRow("Rescan every") {
                    PopUpMenu(selection: $store.settings.refreshInterval, options: [
                        (30.0, Text("30 s")),
                        (60.0, Text("1 min")),
                        (120.0, Text("2 min")),
                        (300.0, Text("5 min")),
                    ])
                    .accessibilityLabel(Text("Rescan every"))
                }
            }
        }
    }
}

/// The version and build shown in About, read from the app's own bundle.
enum AppVersion {
    static var string: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
}

/// Partiti UI's About pane: the icon, a line about Mittari and the version, updates,
/// and a way to support it.
struct AboutView: View {
    @State private var automaticallyChecksForUpdates = Updater.automaticallyChecksForUpdates

    var body: some View {
        ScrollView {
            AboutPane(
                brand: PartitiBrand(
                    accent: MittariStyle.accent,
                    tagline: "Claude Code and Codex usage in your menu bar",
                    coffeeLine: "Mittari is free. If it helps you keep an eye on your limits, you can buy me a coffee.",
                    icon: AppIconView.image),
                version: "Version \(AppVersion.string)",
                checksAutomatically: $automaticallyChecksForUpdates,
                onCheckForUpdates: { Updater.checkForUpdates() },
                onBuyMeACoffee: { ExternalLinks.openBuyMeACoffee() })
                .padding(.top, 44)
                .padding(.horizontal, PUI.Space.xxl)
                .padding(.bottom, PUI.Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: automaticallyChecksForUpdates) { _, enabled in
            Updater.automaticallyChecksForUpdates = enabled
        }
    }
}

struct LimitsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var store = store
        let report = monitor.report
        let limits = store.settings.limits
        MittariPane(pane: .limits, subtitle: "What 100% means, and when the ring changes color.") {
            SettingsGroup("100% is", footer: "Claude plan limits aren't written to the logs, so percentages are estimates against this reference. In Auto, the window or week in progress is left out of the reference, so a new record reads above 100%. Tokens include cache reads and writes, as in ccusage.") {
                RadioRow("Auto", subtitle: "Your busiest earlier 5-hour window in the last 30 days", isOn: limits.mode == .auto) {
                    store.settings.limits.mode = .auto
                }
                RadioRow("Custom token budgets", subtitle: "Set the 5-hour and weekly budgets yourself, in millions of tokens", isOn: limits.mode == .custom) {
                    store.settings.limits.mode = .custom
                }
                if limits.mode == .auto {
                    SettingsRow("Busiest earlier 5-hour window") {
                        ValueText(report.busiestBlockTokens > 0 ? "\(Format.tokens(report.busiestBlockTokens)) tokens" : "Not enough history yet")
                    }
                    SettingsRow("Busiest earlier 7 days") {
                        ValueText(report.busiestWeekTokens > 0 ? "\(Format.tokens(report.busiestWeekTokens)) tokens" : "Not enough history yet")
                    }
                } else {
                    MillionsField(title: "5-hour window budget", tokens: $store.settings.limits.fiveHourTokens)
                    MillionsField(title: "Weekly budget", tokens: $store.settings.limits.weeklyTokens)
                    SettingsRow("Start from your busiest earlier window and week") {
                        Button("Start from Auto Values") {
                            if report.busiestBlockTokens > 0 { store.settings.limits.fiveHourTokens = report.busiestBlockTokens }
                            if report.busiestWeekTokens > 0 { store.settings.limits.weeklyTokens = report.busiestWeekTokens }
                        }
                        .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                    }
                }
            }

            SettingsGroup("Thresholds", footer: "The menu bar ring turns orange at the warning threshold and red at the critical one. You get at most one notification per level and window.") {
                ThresholdPreview(limits: limits, percent: Gauge(report: report, limits: limits, now: monitor.now).fiveHourPercent)
                PercentSlider(title: "Warning at", percent: $store.settings.limits.warningPercent, range: 50...95)
                PercentSlider(title: "Critical at", percent: $store.settings.limits.criticalPercent, range: 60...100)
                SwitchRow("Notify when the 5-hour window crosses a threshold", isOn: $store.settings.limits.notify)
            }
        }
        .onChange(of: store.settings.limits.warningPercent) { _, warning in
            if store.settings.limits.criticalPercent < warning { store.settings.limits.criticalPercent = warning }
        }
    }
}

/// One choice of a radio group inside a settings group, with the mark in the accent.
private struct RadioRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isOn: Bool
    let select: () -> Void
    @Environment(\.puiAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, isOn: Bool, select: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isOn = isOn
        self.select = select
    }

    var body: some View {
        let ink = Ink(colorScheme)
        Button(action: select) {
            HStack(spacing: PUI.Space.m + 2) {
                Circle()
                    .strokeBorder(isOn ? accent.color : ink.tertiary, lineWidth: isOn ? 5 : 1.2)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(PUI.Font.body).foregroundStyle(ink.primary)
                    Text(subtitle).font(PUI.Font.caption).foregroundStyle(ink.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PUI.Space.l)
            .padding(.vertical, PUI.Space.m)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// The three levels as small rings, and the thresholds marked on a meter filled to the
/// current 5-hour window.
private struct ThresholdPreview: View {
    let limits: LimitSettings
    let percent: Double?
    @Environment(\.colorScheme) private var colorScheme

    private let meterWidth: CGFloat = 220

    var body: some View {
        let ink = Ink(colorScheme)
        let warning = limits.warningPercent
        let critical = max(limits.criticalPercent, warning)
        HStack(spacing: PUI.Space.xxl) {
            ring(max(warning - 15, 0), "Normal", .normal, ink)
            ring((warning + critical) / 2, "Warning", .warning, ink)
            ring(min(critical + (100 - critical) / 2, 100), "Critical", .critical, ink)
            Spacer(minLength: PUI.Space.l)
            VStack(alignment: .trailing, spacing: PUI.Space.xs) {
                Meter((percent ?? 0) / 100, color: MittariStyle.color(Gauge.level(percent, limits: limits)), marks: [warning / 100, critical / 100])
                    .frame(width: meterWidth)
                ZStack(alignment: .leading) {
                    tick("0%", at: 0)
                    tick("\(Int(warning))%", at: warning)
                    tick("\(Int(critical))%", at: critical)
                }
                .font(PUI.Font.caption)
                .monospacedDigit()
                .foregroundStyle(ink.tertiary)
                .frame(width: meterWidth, height: 14, alignment: .leading)
            }
        }
        .padding(PUI.Space.l)
    }

    private func ring(_ value: Double, _ name: LocalizedStringKey, _ level: Gauge.Level, _ ink: Ink) -> some View {
        VStack(spacing: PUI.Space.s) {
            GaugeRing(value / 100, color: MittariStyle.color(level), lineWidth: 5, size: 44) {
                Text(verbatim: "\(Int(value.rounded()))%")
                    .font(PUI.Font.label)
                    .monospacedDigit()
                    .foregroundStyle(ink.primary)
            }
            Text(name).font(PUI.Font.caption).foregroundStyle(ink.secondary)
        }
    }

    /// A label centered under `percent` of the meter, kept inside its ends.
    private func tick(_ text: String, at percent: Double) -> some View {
        Text(verbatim: text)
            .fixedSize()
            .frame(width: 32)
            .offset(x: min(max(meterWidth * percent / 100 - 16, -8), meterWidth - 24))
    }
}

/// A token count edited in millions.
private struct MillionsField: View {
    let title: String
    @Binding var tokens: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsRow(title) {
            HStack(spacing: PUI.Space.s) {
                TextField(title, value: Binding(
                    get: { Double(tokens) / 1_000_000 },
                    set: { tokens = max(Int(($0 * 1_000_000).rounded()), 1) }
                ), format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                Text("million tokens")
                    .font(PUI.Font.body)
                    .foregroundStyle(Ink(colorScheme).secondary)
            }
        }
    }
}

/// A threshold in steps of 5%, on Partiti UI's slider.
struct PercentSlider: View {
    let title: String
    @Binding var percent: Double
    var range: ClosedRange<Double> = 0...100

    var body: some View {
        SettingsRow(title) {
            HStack(spacing: PUI.Space.m) {
                PUISlider(value: $percent, in: range, step: 5)
                    .frame(width: 220)
                    .accessibilityLabel(title)
                ValueText("\(Int(percent))%", width: 44)
            }
        }
    }
}

struct DataView: View {
    @Environment(UsageMonitor.self) private var monitor

    var body: some View {
        MittariPane(pane: .data, subtitle: "Where Mittari reads usage from, and what it found.") {
            SettingsGroup("Folders", footer: "Claude Code transcripts in every projects folder found ($CLAUDE_CONFIG_DIR, ~/.config/claude, ~/.claude), and Codex sessions. Mittari only reads these files: it never writes to them and makes no network connections.") {
                ForEach(monitor.folders, id: \.url) { folder in
                    SettingsRow(displayPath(folder.url)) {
                        HStack(spacing: PUI.Space.m) {
                            if folder.exists {
                                ValueText("\(folder.fileCount.formatted()) files")
                                Button("Show") { NSWorkspace.shared.open(folder.url) }
                                    .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                            } else {
                                ValueText("Not found")
                            }
                        }
                    }
                }
            }

            SettingsGroup("Parsed", footer: "Rescan forgets what was read and parses every recent file again. Duplicated messages are counted once.") {
                SettingsRow("Claude Code messages") {
                    ValueText("\(monitor.entryCount.formatted()) in the last year")
                }
                SettingsRow("Codex sessions") {
                    ValueText("\(monitor.report.codex.sessionCount.formatted()) in the last year")
                }
                if let last = monitor.lastScan {
                    SettingsRow("Last scan") {
                        ValueText("\(last.formatted(date: .omitted, time: .standard)), full scan took \(String(format: "%.1f", monitor.lastScanDuration)) s")
                    }
                }
                SettingsRow("Read every recent file again") {
                    HStack(spacing: PUI.Space.m) {
                        if monitor.isScanning { ProgressView().controlSize(.small) }
                        Button("Rescan") { monitor.rescan() }
                            .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                            .disabled(monitor.isScanning)
                    }
                }
            }
        }
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

import MittariCore
import SwiftUI

struct GeneralView: View {
    @Environment(SettingsStore.self) private var store
    @State private var launchAtLogin = LoginItem.status == .enabled
    @State private var automaticallyChecksForUpdates = Updater.automaticallyChecksForUpdates

    var body: some View {
        @Bindable var store = store
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        enabled ? LoginItem.register() : LoginItem.unregister()
                    }
                if LoginItem.status == .requiresApproval {
                    Button("Approve in System Settings…") { LoginItem.openSystemSettings() }
                }
            }
            Section {
                Picker("Rescan every", selection: $store.settings.refreshInterval) {
                    Text("30 s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("New lines in the logs are picked up within a few seconds of being written. The periodic rescan is a fallback, and only reads what changed.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, enabled in
                        Updater.automaticallyChecksForUpdates = enabled
                    }
                Button("Check for Updates Now…") { Updater.checkForUpdates() }
            } header: {
                Text("Updates")
            } footer: {
                Text("Mittari asks once, the first time it can check, whether to check automatically from then on.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Buy Me a Coffee…") { ExternalLinks.openBuyMeACoffee() }
                    .buttonStyle(.link)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AirBackground())
    }
}

struct LimitsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor

    var body: some View {
        @Bindable var store = store
        let report = monitor.report
        Form {
            Section {
                Picker("100% is", selection: $store.settings.limits.mode) {
                    Text("Auto: your busiest earlier 5-hour window in the last 30 days").tag(LimitMode.auto)
                    Text("Custom token budgets").tag(LimitMode.custom)
                }
                .pickerStyle(.radioGroup)
                if store.settings.limits.mode == .auto {
                    LabeledContent("Busiest earlier 5-hour window", value: report.busiestBlockTokens > 0 ? "\(Format.tokens(report.busiestBlockTokens)) tokens" : "Not enough history yet")
                    LabeledContent("Busiest earlier 7 days", value: report.busiestWeekTokens > 0 ? "\(Format.tokens(report.busiestWeekTokens)) tokens" : "Not enough history yet")
                } else {
                    MillionsField(title: "5-hour window budget", tokens: $store.settings.limits.fiveHourTokens)
                    MillionsField(title: "Weekly budget", tokens: $store.settings.limits.weeklyTokens)
                    Button("Start from Auto Values") {
                        if report.busiestBlockTokens > 0 { store.settings.limits.fiveHourTokens = report.busiestBlockTokens }
                        if report.busiestWeekTokens > 0 { store.settings.limits.weeklyTokens = report.busiestWeekTokens }
                    }
                }
            } header: {
                Text("Limits")
            } footer: {
                Text("Claude plan limits aren't written to the logs, so percentages are estimates against this reference. In Auto, the window or week in progress is left out of the reference, so a new record reads above 100%. Tokens include cache reads and writes, as in ccusage.")
                    .foregroundStyle(.secondary)
            }

            Section {
                PercentSlider(title: "Warning at", percent: $store.settings.limits.warningPercent, range: 50...95)
                PercentSlider(title: "Critical at", percent: $store.settings.limits.criticalPercent, range: 60...100)
                Toggle("Notify when the 5-hour window crosses a threshold", isOn: $store.settings.limits.notify)
            } header: {
                Text("Thresholds")
            } footer: {
                Text("The menu bar ring turns orange at the warning threshold and red at the critical one. You get at most one notification per level and window.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AirBackground())
        .onChange(of: store.settings.limits.warningPercent) { _, warning in
            if store.settings.limits.criticalPercent < warning { store.settings.limits.criticalPercent = warning }
        }
    }
}

/// A token count edited in millions.
private struct MillionsField: View {
    let title: String
    @Binding var tokens: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(
                    get: { Double(tokens) / 1_000_000 },
                    set: { tokens = max(Int(($0 * 1_000_000).rounded()), 1) }
                ), format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                Text("million tokens")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PercentSlider: View {
    let title: String
    @Binding var percent: Double
    var range: ClosedRange<Double> = 0...100

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $percent, in: range, step: 5)
                    .tint(Theme.amber)
                Text("\(Int(percent))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(maxWidth: 300)
        }
    }
}

struct DataView: View {
    @Environment(UsageMonitor.self) private var monitor

    var body: some View {
        Form {
            Section {
                ForEach(monitor.folders, id: \.url) { folder in
                    LabeledContent {
                        HStack(spacing: 8) {
                            if folder.exists {
                                Text("\(folder.fileCount) files")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Button("Show") { NSWorkspace.shared.open(folder.url) }
                            } else {
                                Text("Not found")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } label: {
                        Text(verbatim: displayPath(folder.url))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } header: {
                Text("Folders")
            } footer: {
                Text("Claude Code transcripts in every projects folder found ($CLAUDE_CONFIG_DIR, ~/.config/claude, ~/.claude), and Codex sessions. Mittari only reads these files: it never writes to them and makes no network connections.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Claude Code messages", value: "\(monitor.entryCount.formatted()) in the last year")
                LabeledContent("Codex sessions", value: "\(monitor.report.codex.sessionCount) in the last year")
                if let last = monitor.lastScan {
                    LabeledContent("Last scan", value: "\(last.formatted(date: .omitted, time: .standard)), full scan took \(String(format: "%.1f", monitor.lastScanDuration)) s")
                }
                HStack {
                    Spacer()
                    if monitor.isScanning { ProgressView().controlSize(.small) }
                    Button("Rescan") { monitor.rescan() }
                        .disabled(monitor.isScanning)
                }
            } header: {
                Text("Parsed")
            } footer: {
                Text("Rescan forgets what was read and parses every recent file again. Duplicated messages are counted once.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AirBackground())
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

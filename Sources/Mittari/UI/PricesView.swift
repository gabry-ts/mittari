import MittariCore
import PartitiUI
import SwiftUI

/// Editable price history per model. Each message is priced with the period valid at its
/// timestamp, so adding new prices from a date leaves past costs as they were.
struct PricesView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newModelID = ""
    @State private var expanded: Set<String>

    init(expanded: Set<String> = []) {
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        let used = usedModels
        let models = store.settings.prices.models
        let ink = Ink(colorScheme)
        MittariPane(pane: .prices, subtitle: "What each model costs, per million tokens, over time.") {
            SettingsGroup("Prices", footer: "Costs are the API list-price equivalent of your usage, in USD per million tokens. With a Claude subscription you don't pay these amounts.") {
                verification(ink)
                if !monitor.report.unpricedModels.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: PUI.Space.m) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(MittariStyle.warning)
                        Text("No price for \(monitor.report.unpricedModels.joined(separator: ", ")). Its usage shows no cost until you add one below.")
                            .foregroundStyle(ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(PUI.Font.callout)
                    .padding(.horizontal, PUI.Space.l)
                    .padding(.vertical, PUI.Space.m + 2)
                }
            }

            let inUse = models.indices.filter { used.contains(models[$0].id) }
            let others = models.indices.filter { !used.contains(models[$0].id) }
            if !inUse.isEmpty {
                SettingsGroup("Models in your logs") {
                    ForEach(inUse, id: \.self) { modelRow($0, ink) }
                }
            }
            SettingsGroup("Other models") {
                ForEach(others, id: \.self) { modelRow($0, ink) }
                HStack(spacing: PUI.Space.m) {
                    TextField("Model ID, e.g. claude-opus-6", text: $newModelID)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addModel)
                    Button("Add Model", action: addModel)
                        .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                        .disabled(ModelName.normalize(newModelID).isEmpty)
                }
                .padding(.horizontal, PUI.Space.l)
                .padding(.vertical, PUI.Space.m + 2)
            }
        }
    }

    private func verification(_ ink: Ink) -> some View {
        let book = store.settings.prices
        let verified = book.lastVerified
        let stale = verified.map { Date().timeIntervalSince($0) > 180 * 86_400 } ?? true
        return VStack(alignment: .leading, spacing: PUI.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: PUI.Space.m) {
                Image(systemName: stale ? "exclamationmark.triangle.fill" : "clock.badge.checkmark")
                    .font(PUI.Font.callout)
                    .foregroundStyle(stale ? MittariStyle.warning : MittariStyle.accent.legible(colorScheme))
                VStack(alignment: .leading, spacing: PUI.Space.xs) {
                    Text(verified.map { "Prices may be outdated. Last verified \($0.formatted(date: .long, time: .omitted))." } ?? "Prices may be outdated.")
                        .font(PUI.Font.headline)
                        .foregroundStyle(ink.primary)
                    Text("Mittari never goes online, so it can't notice price changes. Compare with Anthropic's pricing page and add a new price from the day it changed:")
                        .font(PUI.Font.caption)
                        .foregroundStyle(ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: PriceBook.sourceURL)
                        .font(PUI.Font.caption.monospaced())
                        .foregroundStyle(ink.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: PUI.Space.m) {
                Spacer()
                Button("Mark as Verified Today") { store.settings.prices.lastVerified = Date() }
                    .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                Button("Restore Defaults") { store.settings.prices = .defaults }
                    .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                    .disabled(book == .defaults)
            }
        }
        .padding(PUI.Space.l)
    }

    private func modelRow(_ index: Int, _ ink: Ink) -> some View {
        let model = store.settings.prices.models[index]
        let current = model.period(at: Date())
        let isExpanded = expanded.contains(model.id)
        return VStack(alignment: .leading, spacing: PUI.Space.m) {
            Button {
                withAnimation(PUI.Motion.spring(reduceMotion: reduceMotion)) { expandedBinding(model.id).wrappedValue.toggle() }
            } label: {
                HStack(spacing: PUI.Space.m) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ink.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ModelName.display(model.id))
                            .font(PUI.Font.body)
                            .foregroundStyle(ink.primary)
                        Text(verbatim: model.id)
                            .font(PUI.Font.caption.monospaced())
                            .foregroundStyle(ink.secondary)
                    }
                    Spacer()
                    Text(verbatim: current.map(summary) ?? "No current price")
                        .font(PUI.Font.callout)
                        .monospacedDigit()
                        .foregroundStyle(ink.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: PUI.Space.l) {
                    ForEach(Array(model.periods.enumerated()), id: \.element.id) { periodIndex, period in
                        PeriodEditor(
                            period: periodBinding(model: index, period: periodIndex),
                            isCurrent: period.id == current?.id,
                            canDelete: model.periods.count > 1,
                            delete: { store.settings.prices.models[index].periods.remove(at: periodIndex) }
                        )
                    }
                    HStack {
                        Button("Add New Price From Today") { addPeriod(to: index) }
                            .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                        Spacer()
                        Button("Remove Model", role: .destructive) {
                            store.settings.prices.models.remove(at: index)
                        }
                        .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                    }
                }
                .padding(.leading, PUI.Space.xl + PUI.Space.xs)
            }
        }
        .padding(.horizontal, PUI.Space.l)
        .padding(.vertical, PUI.Space.m + 2)
    }

    private func summary(_ period: PricePeriod) -> String {
        func price(_ value: Double?) -> String { value.map { "$" + $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "—" }
        return "\(price(period.input)) in · \(price(period.output)) out"
    }

    /// Models that appear in the parsed logs.
    private var usedModels: Set<String> {
        Set(monitor.report.modelsWeek.map(\.id) + monitor.report.unpricedModels)
            .union(Set(monitor.report.entries.suffix(5000).map { ModelName.normalize($0.model) }))
    }

    private func addModel() {
        let id = ModelName.normalize(newModelID.trimmingCharacters(in: .whitespaces))
        guard !id.isEmpty, !store.settings.prices.models.contains(where: { $0.id == id }) else { return }
        store.settings.prices.models.append(ModelPricing(id: id, periods: [PricePeriod(
            input: nil, output: nil, cacheWrite5m: nil, cacheWrite1h: nil, cacheRead: nil, source: "Added by you"
        )]))
        expanded.insert(id)
        newModelID = ""
    }

    /// Starts new prices today, pre-filled with the current ones.
    private func addPeriod(to index: Int) {
        let today = Calendar.current.startOfDay(for: Date())
        var period = store.settings.prices.models[index].period(at: Date()) ?? PricePeriod(
            input: nil, output: nil, cacheWrite5m: nil, cacheWrite1h: nil, cacheRead: nil
        )
        period.id = UUID()
        period.from = today
        period.to = nil
        period.source = "Added by you"
        store.settings.prices.models[index].periods.append(period)
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } }
        )
    }

    private func periodBinding(model: Int, period: Int) -> Binding<PricePeriod> {
        Binding(
            get: { store.settings.prices.models[model].periods[period] },
            set: { store.settings.prices.models[model].periods[period] = $0 }
        )
    }
}

/// One price period: its dates and the five prices.
private struct PeriodEditor: View {
    @Binding var period: PricePeriod
    let isCurrent: Bool
    let canDelete: Bool
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = Ink(colorScheme)
        VStack(alignment: .leading, spacing: PUI.Space.m) {
            HStack(spacing: PUI.Space.m) {
                dateField("From", date: $period.from, empty: "Since release")
                dateField("Until", date: $period.to, empty: "Open-ended")
                if isCurrent {
                    Badge("Current")
                }
                Spacer()
                if canDelete {
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                            .font(PUI.Font.callout)
                            .foregroundStyle(ink.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this period")
                }
            }
            Grid(alignment: .leading, horizontalSpacing: PUI.Space.m + 2, verticalSpacing: PUI.Space.xs) {
                GridRow {
                    ForEach(Self.columns, id: \.0) { column in
                        Text(column.0)
                            .font(PUI.Font.caption)
                            .foregroundStyle(ink.secondary)
                    }
                }
                GridRow {
                    ForEach(Self.columns, id: \.0) { column in
                        TextField(column.0, value: $period[dynamicMember: column.1], format: .number.precision(.fractionLength(0...4)))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 96)
                    }
                }
            }
            if let source = period.source {
                Text(source)
                    .font(PUI.Font.caption)
                    .foregroundStyle(ink.tertiary)
            }
        }
        .padding(PUI.Space.m + 2)
        .background(isCurrent ? ink.strongFill : ink.fill, in: .rect(cornerRadius: PUI.Radius.group, style: .continuous))
    }

    private static let columns: [(String, WritableKeyPath<PricePeriod, Double?>)] = [
        ("Input", \.input), ("Output", \.output), ("Cache write 5m", \.cacheWrite5m),
        ("Cache write 1h", \.cacheWrite1h), ("Cache read", \.cacheRead),
    ]

    @ViewBuilder
    private func dateField(_ title: String, date: Binding<Date?>, empty: String) -> some View {
        HStack(spacing: PUI.Space.xs) {
            Text(title)
                .font(PUI.Font.caption)
                .foregroundStyle(Ink(colorScheme).secondary)
            if let value = date.wrappedValue {
                DatePicker(title, selection: Binding(get: { value }, set: { date.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                Button {
                    date.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Ink(colorScheme).tertiary)
                .help("Clear")
            } else {
                Button(empty) { date.wrappedValue = Calendar.current.startOfDay(for: Date()) }
                    .buttonStyle(.borderless)
                    .font(PUI.Font.callout)
                    .foregroundStyle(MittariStyle.accent.legible(colorScheme))
                    .help("Set a date")
            }
        }
    }
}

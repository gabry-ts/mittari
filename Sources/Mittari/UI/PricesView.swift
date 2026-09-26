import MittariCore
import SwiftUI

/// Editable price history per model. Each message is priced with the period valid at its
/// timestamp, so adding new prices from a date leaves past costs as they were.
struct PricesView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor
    @State private var newModelID = ""
    @State private var expanded: Set<String>

    init(expanded: Set<String> = []) {
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        let used = usedModels
        let models = store.settings.prices.models
        Form {
            Section {
                verification
                if !monitor.report.unpricedModels.isEmpty {
                    Label {
                        Text("No price for \(monitor.report.unpricedModels.joined(separator: ", ")). Its usage shows no cost until you add one below.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                    }
                    .font(.callout)
                }
            } header: {
                Text("Prices")
            } footer: {
                Text("Costs are the API list-price equivalent of your usage, in USD per million tokens. With a Claude subscription you don't pay these amounts.")
                    .foregroundStyle(.secondary)
            }

            let inUse = models.indices.filter { used.contains(models[$0].id) }
            let others = models.indices.filter { !used.contains(models[$0].id) }
            if !inUse.isEmpty {
                Section("Models in your logs") {
                    ForEach(inUse, id: \.self) { modelRow($0) }
                }
            }
            Section("Other models") {
                ForEach(others, id: \.self) { modelRow($0) }
                HStack {
                    TextField("Model ID, e.g. claude-opus-6", text: $newModelID)
                        .onSubmit(addModel)
                    Button("Add Model", action: addModel)
                        .disabled(ModelName.normalize(newModelID).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AirBackground())
    }

    private var verification: some View {
        let book = store.settings.prices
        let verified = book.lastVerified
        let stale = verified.map { Date().timeIntervalSince($0) > 180 * 86_400 } ?? true
        return VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verified.map { "Prices may be outdated. Last verified \($0.formatted(date: .long, time: .omitted))." } ?? "Prices may be outdated.")
                        .font(.callout.weight(.semibold))
                    Text("Mittari never goes online, so it can't notice price changes. Compare with Anthropic's pricing page and add a new price from the day it changed:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: PriceBook.sourceURL)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } icon: {
                Image(systemName: stale ? "exclamationmark.triangle.fill" : "clock.badge.checkmark")
                    .foregroundStyle(stale ? Theme.warning : Theme.amber)
            }
            HStack {
                Spacer()
                Button("Mark as Verified Today") { store.settings.prices.lastVerified = Date() }
                Button("Restore Defaults") { store.settings.prices = .defaults }
                    .disabled(book == .defaults)
            }
        }
    }

    private func modelRow(_ index: Int) -> some View {
        let model = store.settings.prices.models[index]
        let current = model.period(at: Date())
        return DisclosureGroup(isExpanded: expandedBinding(model.id)) {
            VStack(alignment: .leading, spacing: 12) {
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
                    Spacer()
                    Button("Remove Model", role: .destructive) {
                        store.settings.prices.models.remove(at: index)
                    }
                }
                .controlSize(.small)
            }
            .padding(.vertical, 6)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ModelName.display(model.id))
                    Text(verbatim: model.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: current.map(summary) ?? "No current price")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                dateField("From", date: $period.from, empty: "Since release")
                dateField("Until", date: $period.to, empty: "Open-ended")
                if isCurrent {
                    Text("Current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.amber, in: .capsule)
                }
                Spacer()
                if canDelete {
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this period")
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    ForEach(Self.columns, id: \.0) { column in
                        Text(column.0)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.primary.opacity(isCurrent ? 0.05 : 0.025), in: .rect(cornerRadius: 10))
    }

    private static let columns: [(String, WritableKeyPath<PricePeriod, Double?>)] = [
        ("Input", \.input), ("Output", \.output), ("Cache write 5m", \.cacheWrite5m),
        ("Cache write 1h", \.cacheWrite1h), ("Cache read", \.cacheRead),
    ]

    @ViewBuilder
    private func dateField(_ title: String, date: Binding<Date?>, empty: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.tertiary)
                .help("Clear")
            } else {
                Button(empty) { date.wrappedValue = Calendar.current.startOfDay(for: Date()) }
                    .buttonStyle(.borderless)
                    .help("Set a date")
            }
        }
    }
}

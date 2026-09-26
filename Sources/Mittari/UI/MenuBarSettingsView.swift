import MittariCore
import SwiftUI
import UniformTypeIdentifiers

/// Menu bar settings: a draggable status item strip, with a live preview on the right.
struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var draggingItem: Int?
    @State private var editingItem: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            AirPage(title: "Menu Bar", subtitle: "What sits in the menu bar, in the order you like.", drawsBackground: false) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardTitle(title: "Status Item", systemImage: "menubar.rectangle")
                        statusStrip
                        Text("Drag to reorder. Click an item to remove it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        CardTitle(title: "Available Items", systemImage: "square.grid.2x2")
                        ForEach(StatusElement.allCases, id: \.self) { element in
                            itemRow(element)
                        }
                    }
                }
            }
            MenuBarPreview(showsPopover: false)
                .frame(width: 340)
        }
        .background(AirBackground())
    }

    private var statusStrip: some View {
        let items = store.settings.menuBar.items
        return HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                StatusChip(item: item, isDragging: draggingItem == index)
                    .onTapGesture { editingItem = index }
                    .popover(isPresented: editingBinding(index), arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.title)
                                .foregroundStyle(.secondary)
                            Button("Remove", role: .destructive) {
                                editingItem = nil
                                store.settings.menuBar.items.remove(at: index)
                            }
                        }
                        .padding(14)
                        .frame(minWidth: 200)
                    }
                    .reorderable(index: index, items: itemsBinding, dragging: $draggingItem)
            }
            addItemMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
        .animation(.snappy, value: items)
    }

    private func itemRow(_ element: StatusElement) -> some View {
        let isOn = Binding(
            get: { store.settings.menuBar.items.contains(element) },
            set: { on in
                if on {
                    if !store.settings.menuBar.items.contains(element) { store.settings.menuBar.items.append(element) }
                } else {
                    store.settings.menuBar.items.removeAll { $0 == element }
                }
            }
        )
        return HStack(spacing: 10) {
            Image(systemName: element.icon)
                .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(.secondary))
                .frame(width: 20)
            Text(element.title)
            Spacer()
            Toggle(element.title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.amber)
        }
    }

    private var addItemMenu: some View {
        Menu {
            ForEach(StatusElement.allCases, id: \.self) { element in
                Button(element.title) { store.settings.menuBar.items.append(element) }
                    .disabled(store.settings.menuBar.items.contains(element))
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add an item")
    }

    private func editingBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { editingItem == index },
            set: { if !$0 { editingItem = nil } }
        )
    }

    private var itemsBinding: Binding<[StatusElement]> {
        Binding(
            get: { store.settings.menuBar.items },
            set: { store.settings.menuBar.items = $0 }
        )
    }
}

/// Popover settings: draggable sections that switch on and off, with a live preview.
struct PopoverSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var draggingSection: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            AirPage(title: "Popover", subtitle: "What opens under the menu bar item.", drawsBackground: false) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardTitle(title: "Sections", systemImage: "rectangle.stack")
                        sections
                        Text("Drag to reorder. Switch off what you don't need.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            MenuBarPreview(showsPopover: true)
                .frame(width: 360)
        }
        .background(AirBackground())
    }

    private var sections: some View {
        let sections = store.settings.popover.sections
        return VStack(spacing: 6) {
            ForEach(Array(sections.enumerated()), id: \.element.section) { index, entry in
                sectionCard(index: index, entry: entry)
                    .reorderable(index: index, items: sectionsBinding, dragging: $draggingSection)
            }
        }
        .animation(.snappy, value: sections)
    }

    private func sectionCard(index: Int, entry: PopoverEntry) -> some View {
        @Bindable var store = store
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Image(systemName: entry.section.icon)
                .foregroundStyle(entry.isEnabled ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(.secondary))
                .frame(width: 20)
            Text(entry.section.title)
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)
            Spacer()
            Toggle(entry.section.title, isOn: $store.settings.popover.sections[index].isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.amber)
        }
        .padding(12)
        .background(.primary.opacity(entry.isEnabled ? 0.05 : 0.025), in: .rect(cornerRadius: 12))
        .opacity(draggingSection == index ? 0.5 : 1)
        .contentShape(.rect)
    }

    private var sectionsBinding: Binding<[PopoverEntry]> {
        Binding(
            get: { store.settings.popover.sections },
            set: { store.settings.popover.sections = $0 }
        )
    }
}

// MARK: - Pieces

/// One item in the status item strip, drawn like the real menu bar.
private struct StatusChip: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    let item: StatusElement
    let isDragging: Bool
    @State private var isHovering = false

    var body: some View {
        content
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isHovering ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
            .opacity(isDragging ? 0.4 : 1)
            .contentShape(.rect)
            .onHover { isHovering = $0 }
            .help(item.title)
    }

    @ViewBuilder
    private var content: some View {
        let gauge = Gauge(report: monitor.report, limits: store.settings.limits, now: monitor.now)
        let tint: NSColor = colorScheme == .dark ? .white : .black
        switch item {
        case .gauge:
            Image(nsImage: StatusImage.ring(percent: gauge.block == nil ? 0 : gauge.fiveHourPercent ?? 0, level: gauge.level, tint: tint))
        case .percent:
            Text(verbatim: "5h " + Gauge.percentText(gauge.block == nil ? 0 : gauge.fiveHourPercent))
        case .weekGauge:
            Image(nsImage: StatusImage.ring(percent: gauge.weekPercent ?? 0,
                                            level: Gauge.level(gauge.weekPercent, limits: store.settings.limits), tint: tint))
        case .weekPercent:
            Text(verbatim: "7d " + Gauge.percentText(gauge.weekPercent))
        case .resetTime:
            Text(verbatim: gauge.timeToReset(now: monitor.now).map(Format.duration) ?? "–")
        case .tokensToday:
            Text(verbatim: Format.tokens(monitor.report.today.tokens.total))
        case .costToday:
            Text(verbatim: Format.cost(monitor.report.today.cost))
        }
    }
}

/// The status item and popover as they look right now, not interactive.
private struct MenuBarPreview: View {
    @Environment(SettingsStore.self) private var store
    @Environment(UsageMonitor.self) private var monitor
    let showsPopover: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            CardTitle(title: "Live Preview", systemImage: "eye")
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
                MenuBarLabel(store: store, monitor: monitor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.fill.secondary, in: .rect(cornerRadius: 5))
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 10))
            if showsPopover {
                MenuContent(openStatistics: {}, openSettings: {})
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 88)
    }
}

// MARK: - Drag to reorder

private struct ReorderDropDelegate<Item>: DropDelegate {
    let index: Int
    @Binding var items: [Item]
    @Binding var dragging: Int?

    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != index, items.indices.contains(from) else { return }
        items.move(fromOffsets: [from], toOffset: index > from ? index + 1 : index)
        dragging = index
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension View {
    /// Live drag-and-drop reordering within one list. Each list needs its own `dragging`
    /// state, so drags never leak between lists.
    fileprivate func reorderable<Item>(index: Int, items: Binding<[Item]>, dragging: Binding<Int?>) -> some View {
        onDrag {
            dragging.wrappedValue = index
            return NSItemProvider(object: String(index) as NSString)
        }
        .onDrop(of: [.text], delegate: ReorderDropDelegate(index: index, items: items, dragging: dragging))
    }
}

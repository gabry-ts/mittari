import MittariCore
import PartitiUI
import SwiftUI
import UniformTypeIdentifiers

/// Menu bar settings: a draggable status item strip, with a live preview on the right.
struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var store
    @State private var draggingItem: Int?
    @State private var editingItem: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            MittariPane(pane: .menuBar, subtitle: "What sits in the menu bar, in the order you like.") {
                SettingsGroup("Status Item", footer: "Drag to reorder. Click an item to remove it.") {
                    statusStrip
                        .padding(PUI.Space.l)
                }
                SettingsGroup("Available Items") {
                    ForEach(StatusElement.allCases, id: \.self) { element in
                        itemRow(element)
                    }
                }
            }
            MenuBarPreview(showsPopover: false)
                .frame(width: 340)
        }
    }

    private var statusStrip: some View {
        let items = store.settings.menuBar.items
        return HStack(spacing: PUI.Space.s) {
            Spacer(minLength: 0)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                StatusChip(item: item, isDragging: draggingItem == index)
                    .onTapGesture { editingItem = index }
                    .popover(isPresented: editingBinding(index), arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: PUI.Space.l) {
                            Text(item.title)
                                .font(PUI.Font.body)
                                .foregroundStyle(Ink(colorScheme).secondary)
                            Button("Remove", role: .destructive) {
                                editingItem = nil
                                store.settings.menuBar.items.remove(at: index)
                            }
                            .buttonStyle(SecondaryButtonStyle(height: PUI.Control.small))
                        }
                        .padding(PUI.Space.l)
                        .frame(minWidth: 200)
                    }
                    .reorderable(index: index, items: itemsBinding, dragging: $draggingItem)
            }
            addItemMenu
        }
        .padding(.horizontal, PUI.Space.m + 2)
        .padding(.vertical, PUI.Space.s)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Ink(colorScheme).fill, in: .rect(cornerRadius: PUI.Radius.group, style: .continuous))
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
        return SymbolRow(symbol: element.icon, title: element.title, isOn: isOn.wrappedValue) {
            Toggle(element.title, isOn: isOn)
                .toggleStyle(PUISwitchStyle(showsLabel: false))
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
                .font(.system(size: PUI.Control.smallSymbol, weight: .medium))
                .foregroundStyle(Ink(colorScheme).secondary)
                .frame(width: PUI.Control.small, height: PUI.Control.small)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
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
        let sections = store.settings.popover.sections
        HStack(alignment: .top, spacing: 0) {
            MittariPane(pane: .popover, subtitle: "What opens under the menu bar item.") {
                SettingsGroup("Sections", footer: "Drag to reorder. Switch off what you don't need.") {
                    ForEach(Array(sections.enumerated()), id: \.element.section) { index, entry in
                        sectionRow(index: index, entry: entry)
                            .reorderable(index: index, items: sectionsBinding, dragging: $draggingSection)
                    }
                }
                .animation(.snappy, value: sections)
            }
            MenuBarPreview(showsPopover: true)
                .frame(width: 360)
        }
    }

    private func sectionRow(index: Int, entry: PopoverEntry) -> some View {
        @Bindable var store = store
        return SymbolRow(symbol: entry.section.icon, title: entry.section.title, isOn: entry.isEnabled, showsHandle: true) {
            Toggle(entry.section.title, isOn: $store.settings.popover.sections[index].isEnabled)
                .toggleStyle(PUISwitchStyle(showsLabel: false))
        }
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

/// A settings row led by a symbol, in the accent while its item is on, with an optional
/// drag handle for rows that reorder.
private struct SymbolRow<Control: View>: View {
    let symbol: String
    let title: String
    let isOn: Bool
    var showsHandle = false
    @ViewBuilder let control: Control
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = Ink(colorScheme)
        HStack(spacing: PUI.Space.m + 2) {
            if showsHandle {
                Image(systemName: "line.3.horizontal")
                    .font(PUI.Font.callout)
                    .foregroundStyle(ink.tertiary)
            }
            RowSymbol(symbol, color: isOn ? MittariStyle.accent.legible(colorScheme) : ink.secondary)
            Text(verbatim: title)
                .font(PUI.Font.body)
                .foregroundStyle(isOn ? ink.primary : ink.secondary)
            Spacer(minLength: PUI.Space.l)
            control
        }
        .padding(.horizontal, PUI.Space.l)
        .padding(.vertical, PUI.Space.m)
        .frame(minHeight: 38)
    }
}

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
            .font(PUI.Font.menuBar)
            .padding(.horizontal, PUI.Space.m)
            .padding(.vertical, 3)
            .puiHoverHighlight(isHovering, radius: 5)
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = Ink(colorScheme)
        let popoverShape = RoundedRectangle(cornerRadius: PUI.Radius.popover, style: .continuous)
        VStack(alignment: .trailing, spacing: PUI.Space.s) {
            SectionHeader("Live Preview")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PUI.Space.xs)
            HStack {
                Spacer()
                MenuBarItem(highlighted: showsPopover, color: ink.primary) {
                    MenuBarLabel(store: store, monitor: monitor)
                }
            }
            .padding(.horizontal, PUI.Space.m)
            .frame(height: 30)
            .background(ink.fill, in: .rect(cornerRadius: PUI.Radius.group, style: .continuous))
            if showsPopover {
                // Scrolls on its own, so a tall popover never forces the window taller.
                ScrollView {
                    MenuContent(openStatistics: {}, openSettings: {})
                        .puiGlass(popoverShape)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .allowsHitTesting(false)
                        .padding(.vertical, PUI.Space.l)
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PUI.Space.xl + PUI.Space.xs)
        .padding(.top, PUI.Space.xxl + PUI.Space.xs)
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

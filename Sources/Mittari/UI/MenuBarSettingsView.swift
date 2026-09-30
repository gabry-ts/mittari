import MittariCore
import PartitiUI
import SwiftUI

/// Menu bar settings: the status item's pieces in a list to switch on and drag into
/// order, with a live preview on the right.
struct MenuBarSettingsView: View {
    @Environment(SettingsStore.self) private var store
    /// Every piece in the order of the list, once the user has touched it. The settings
    /// only keep the pieces that are shown, so the place of the others lives here.
    @State private var order: [StatusElement]?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            MittariPane(pane: .menuBar, subtitle: "What sits in the menu bar, in the order you like.") {
                ReorderableGroup("Status Item",
                                 footer: "Drag to reorder. Switch off what you don't need: with everything off, the 5-hour ring stays.",
                                 items: rows, isOn: isShown) { element in
                    ReorderableLabel(element.title, symbol: element.icon)
                }
            }
            MenuBarPreview(showsPopover: false)
                .frame(width: 340)
        }
    }

    /// The shown pieces in their saved order, then the ones that are off.
    private var elements: [StatusElement] {
        order ?? Reorder.normalized(store.settings.menuBar.items, known: StatusElement.allCases)
    }

    private var rows: Binding<[StatusElement]> {
        Binding(
            get: { elements },
            set: { save($0, shown: Set(store.settings.menuBar.items)) })
    }

    private func isShown(_ element: StatusElement) -> Binding<Bool> {
        Binding(
            get: { store.settings.menuBar.items.contains(element) },
            set: { on in
                var shown = Set(store.settings.menuBar.items)
                if on { shown.insert(element) } else { shown.remove(element) }
                save(elements, shown: shown)
            })
    }

    /// Keeps the list order, and saves the shown pieces in that order.
    private func save(_ elements: [StatusElement], shown: Set<StatusElement>) {
        order = elements
        store.settings.menuBar.items = elements.filter(shown.contains)
    }
}

/// Popover settings: sections to switch on and drag into order, with a live preview.
struct PopoverSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .top, spacing: 0) {
            MittariPane(pane: .popover, subtitle: "What opens under the menu bar item.") {
                ReorderableGroup("Sections", footer: "Drag to reorder. Switch off what you don't need.",
                                 items: $store.settings.popover.sections, isOn: \.isEnabled) { entry in
                    ReorderableLabel(entry.section.title, symbol: entry.section.icon)
                }
            }
            MenuBarPreview(showsPopover: true)
                .frame(width: 360)
        }
    }
}

// MARK: - Pieces

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

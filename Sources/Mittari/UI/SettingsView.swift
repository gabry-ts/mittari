import MittariCore
import SwiftUI

struct SettingsView: View {
    @State private var selection: Pane?
    /// Models whose price history starts expanded, for snapshots.
    private let expandedModels: Set<String>

    enum Pane: String, CaseIterable, Hashable {
        case general
        case menuBar
        case popover
        case limits
        case prices
        case data

        var title: String {
            switch self {
            case .general: "General"
            case .menuBar: "Menu Bar"
            case .popover: "Popover"
            case .limits: "Limits"
            case .prices: "Prices"
            case .data: "Data"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .menuBar: "menubar.rectangle"
            case .popover: "rectangle.stack"
            case .limits: "gauge.with.dots.needle.67percent"
            case .prices: "dollarsign.circle"
            case .data: "folder"
            }
        }
    }

    init(initialSelection: Pane = .general, expandedModels: Set<String> = []) {
        _selection = State(initialValue: initialSelection)
        self.expandedModels = expandedModels
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach([Pane.general, .menuBar, .popover], id: \.self, content: paneRow)
                }
                Section("Usage") {
                    ForEach([Pane.limits, .prices, .data], id: \.self, content: paneRow)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AirBackground())
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
        }
        .frame(minWidth: 880, minHeight: 560)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private func paneRow(_ pane: Pane) -> some View {
        Label(pane.title, systemImage: pane.icon)
            .tag(pane)
    }

    @ViewBuilder
    private var detail: some View {
        if let selection {
            paneView(selection)
                .navigationTitle(selection.title)
        } else {
            ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
        }
    }

    @ViewBuilder
    private func paneView(_ pane: Pane) -> some View {
        switch pane {
        case .general: GeneralView()
        case .menuBar: MenuBarSettingsView()
        case .popover: PopoverSettingsView()
        case .limits: LimitsView()
        case .prices: PricesView(expanded: expandedModels)
        case .data: DataView()
        }
    }
}

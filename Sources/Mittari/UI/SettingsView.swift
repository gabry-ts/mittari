import MittariCore
import Observation
import SwiftUI

/// Which page the main window shows, so the popover can open it on a given page.
@MainActor
@Observable
final class Navigation {
    var pane: SettingsView.Pane?

    init(pane: SettingsView.Pane = .statistics) {
        self.pane = pane
    }
}

/// The main window: statistics first, then every settings page, in one sidebar.
struct SettingsView: View {
    @Bindable var navigation: Navigation
    /// Models whose price history starts expanded, for snapshots.
    private let expandedModels: Set<String>

    enum Pane: String, CaseIterable, Hashable {
        case statistics
        case general
        case menuBar
        case popover
        case limits
        case prices
        case data

        var title: String {
            switch self {
            case .statistics: "Statistics"
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
            case .statistics: "chart.bar.xaxis"
            case .general: "gearshape"
            case .menuBar: "menubar.rectangle"
            case .popover: "rectangle.stack"
            case .limits: "gauge.with.dots.needle.67percent"
            case .prices: "dollarsign.circle"
            case .data: "folder"
            }
        }
    }

    init(navigation: Navigation, expandedModels: Set<String> = []) {
        self.navigation = navigation
        self.expandedModels = expandedModels
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                Section {
                    paneRow(.statistics)
                }
                Section("Settings") {
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
        .frame(minWidth: 900, minHeight: 600)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private func paneRow(_ pane: Pane) -> some View {
        Label(pane.title, systemImage: pane.icon)
            .tag(pane)
    }

    @ViewBuilder
    private var detail: some View {
        if let pane = navigation.pane {
            paneView(pane)
                .navigationTitle(pane.title)
        } else {
            ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
        }
    }

    @ViewBuilder
    private func paneView(_ pane: Pane) -> some View {
        switch pane {
        case .statistics: StatisticsView()
        case .general: GeneralView()
        case .menuBar: MenuBarSettingsView()
        case .popover: PopoverSettingsView()
        case .limits: LimitsView()
        case .prices: PricesView(expanded: expandedModels)
        case .data: DataView()
        }
    }
}

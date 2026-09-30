import MittariCore
import Observation
import PartitiUI
import SwiftUI

/// Which page the main window shows, so the popover can open it on a given page.
@MainActor
@Observable
final class Navigation {
    var pane: SettingsView.Pane

    init(pane: SettingsView.Pane = .statistics) {
        self.pane = pane
    }
}

/// The main window: statistics first, then every settings page, in Partiti UI's floating
/// sidebar.
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
        case about

        var title: String {
            switch self {
            case .statistics: "Statistics"
            case .general: "General"
            case .menuBar: "Menu Bar"
            case .popover: "Popover"
            case .limits: "Limits"
            case .prices: "Prices"
            case .data: "Data"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .statistics: "chart.bar.xaxis"
            case .general: "gearshape.fill"
            case .menuBar: "menubar.rectangle"
            case .popover: "rectangle.stack.fill"
            case .limits: "gauge.with.dots.needle.67percent"
            case .prices: "dollarsign"
            case .data: "folder.fill"
            case .about: "info"
            }
        }

        /// The tile color behind the icon, as in System Settings.
        var tint: Color {
            switch self {
            case .statistics: MittariStyle.accent.color
            case .general: .gray
            case .menuBar: .blue
            case .popover: .indigo
            case .limits: .orange
            case .prices: .green
            case .data: .cyan
            case .about: .teal
            }
        }

        var sidebarItem: SidebarItem {
            SidebarItem(Text(verbatim: title), id: rawValue, symbol: icon, style: .tile(tint))
        }
    }

    init(navigation: Navigation, expandedModels: Set<String> = []) {
        self.navigation = navigation
        self.expandedModels = expandedModels
    }

    private static let sections: [SidebarSection] = [
        SidebarSection(nil, [Pane.statistics.sidebarItem]),
        SidebarSection("Settings", [Pane.general, .menuBar, .popover].map(\.sidebarItem)),
        SidebarSection("Usage", [Pane.limits, .prices, .data].map(\.sidebarItem)),
        SidebarSection(nil, [Pane.about.sidebarItem]),
    ]

    var body: some View {
        SettingsWindow(sections: Self.sections, selection: selection) {
            paneView(navigation.pane)
        }
        // The sidebar leaves room for the traffic lights itself, so it runs under the
        // transparent title bar instead of below it.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: PUI.Window.dashboardMin.width, minHeight: PUI.Window.dashboardMin.height)
        .puiAccent(MittariStyle.accent)
    }

    /// The sidebar selects by the pane's raw value, the id of its item.
    private var selection: Binding<String> {
        Binding(
            get: { navigation.pane.rawValue },
            set: { id in
                if let pane = Pane(rawValue: id) { navigation.pane = pane }
            })
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
        case .about: AboutView()
        }
    }
}

/// A scrolling settings pane opening with Partiti UI's header for `pane`.
struct MittariPane<Content: View>: View {
    let pane: SettingsView.Pane
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            SettingsPane {
                PaneHeader(pane.title, subtitle: subtitle, symbol: pane.icon, color: pane.tint)
            } content: {
                content
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

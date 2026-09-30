import PartitiUI
import SwiftUI

/// Mittari's own colors, for what Partiti UI leaves to each app: the levels a window goes
/// through as it fills up, and the series of charts and breakdowns. Amber is the normal
/// level; orange and coral only appear when a window gets close to its limit.
enum MittariStyle {
    static let accent = AppAccent.mittari
    static let warning = Color(red: 0.97, green: 0.47, blue: 0.18)
    static let critical = Color(red: 0.91, green: 0.27, blue: 0.30)

    static func color(_ level: Gauge.Level) -> Color {
        switch level {
        case .normal: accent.color
        case .warning: warning
        case .critical: critical
        }
    }

    /// Series colors for charts and breakdowns, amber first.
    static let series: [Color] = [
        accent.color,
        Color(red: 0.36, green: 0.64, blue: 1.0),
        Color(red: 0.62, green: 0.52, blue: 0.95),
        Color(red: 0.30, green: 0.78, blue: 0.70),
        Color(red: 0.95, green: 0.45, blue: 0.42),
    ]

    /// Readable width of the statistics dashboard in wide windows.
    static let dashboardMaxWidth: CGFloat = 860
}

import AppKit
import MittariCore
import SwiftUI

/// The status item as a view, for the live preview in settings.
struct MenuBarLabel: View {
    let store: SettingsStore
    let monitor: UsageMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = StatusImage.render(store: store, monitor: monitor, textColor: colorScheme == .dark ? .white : .black) {
            Image(nsImage: image)
        }
    }
}

/// What the status item shows: readings as real menu bar text, so they match the clock
/// and other system items exactly, and the ring gauge as an image.
struct StatusContent {
    var icon: NSImage?
    /// Whether the icon sits before the text; the text is kept together.
    var iconLeading = true
    var title = ""
}

@MainActor
enum StatusImage {
    /// The system menu bar font, with fixed-width digits so readings don't jitter.
    static let font: NSFont = {
        let base = NSFont.menuBarFont(ofSize: 0)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }()

    private static let separator = "  "

    /// Reads every observable input up front, so observation tracking around this call
    /// sees them all.
    static func content(store: SettingsStore, monitor: UsageMonitor) -> StatusContent {
        let settings = store.settings
        let report = monitor.report
        let now = monitor.now
        let gauge = Gauge(report: report, limits: settings.limits, now: now)
        let items = settings.menuBar.displayedItems
        let texts: [String] = items.compactMap { item in
            switch item {
            case .gauge: nil
            case .percent: Gauge.percentText(gauge.fiveHourPercent)
            case .resetTime: gauge.timeToReset(now: now).map(Format.duration) ?? "–"
            case .tokensToday: Format.tokens(report.today.tokens.total)
            case .costToday: report.today.isEmpty ? "$0.00" : Format.cost(report.today.costIsPartial && report.today.cost == 0 ? nil : report.today.cost)
            }
        }
        let iconIndex = items.firstIndex(of: .gauge)
        return StatusContent(
            icon: iconIndex == nil ? nil : ring(percent: gauge.block == nil ? 0 : gauge.fiveHourPercent ?? 0, level: gauge.level),
            iconLeading: iconIndex == 0,
            title: texts.joined(separator: separator)
        )
    }

    /// A ring filled to `percent`. A template image while normal, so it follows the menu
    /// bar's color; orange or red once a threshold is crossed.
    static func ring(percent: Double, level: Gauge.Level) -> NSImage {
        let side = (font.pointSize + 3).rounded()
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let color: NSColor = switch level {
            case .normal: .black
            case .warning: NSColor(Theme.warning)
            case .critical: NSColor(Theme.critical)
            }
            let lineWidth: CGFloat = 2.2
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = (side - lineWidth) / 2 - 0.5
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            color.withAlphaComponent(level == .normal ? 0.3 : 0.35).setStroke()
            track.stroke()
            let fraction = min(max(percent / 100, 0), 1)
            if fraction > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = level == .normal
        image.accessibilityDescription = "Mittari"
        return image
    }

    /// The whole status item as one image, for the preview in settings.
    static func render(store: SettingsStore, monitor: UsageMonitor, textColor: NSColor) -> NSImage? {
        let content = content(store: store, monitor: monitor)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let titleSize = content.title.isEmpty ? .zero : (content.title as NSString).size(withAttributes: attributes)
        let iconSide = content.icon?.size.width ?? 0
        let gap: CGFloat = content.icon != nil && !content.title.isEmpty ? 4 : 0
        let height = max(titleSize.height, iconSide)
        let size = NSSize(width: ceil(iconSide + gap + titleSize.width), height: ceil(height))
        let image = NSImage(size: size, flipped: false) { _ in
            let textX = content.iconLeading ? iconSide + gap : 0
            let iconX = content.iconLeading ? 0 : titleSize.width + gap
            if let icon = content.icon {
                let iconRect = NSRect(x: iconX, y: (height - iconSide) / 2, width: iconSide, height: iconSide)
                if icon.isTemplate {
                    // Tint the template like the menu bar would.
                    let tinted = NSImage(size: icon.size, flipped: false) { r in
                        icon.draw(in: r)
                        textColor.set()
                        r.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: iconRect)
                } else {
                    icon.draw(in: iconRect)
                }
            }
            (content.title as NSString).draw(at: NSPoint(x: textX, y: (height - titleSize.height) / 2), withAttributes: attributes)
            return true
        }
        return image
    }
}

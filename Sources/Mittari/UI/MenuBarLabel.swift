import AppKit
import MittariCore
import SwiftUI

/// The status item as a view, for the live preview in settings.
struct MenuBarLabel: View {
    let store: SettingsStore
    let monitor: UsageMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: StatusImage.render(StatusImage.parts(store: store, monitor: monitor),
                                          textColor: colorScheme == .dark ? .white : .black))
    }
}

/// One piece of the status item: a ring gauge or a reading.
enum StatusPart: Equatable {
    case ring(percent: Double, level: Gauge.Level)
    case text(String)
}

/// What the status item shows. Everything is one attributed title, readings as real menu
/// bar text so they match the clock and other system items, rings as inline images.
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

    /// Reads every observable input up front, so observation tracking around this call
    /// sees them all.
    static func parts(store: SettingsStore, monitor: UsageMonitor) -> [StatusPart] {
        let settings = store.settings
        let report = monitor.report
        let now = monitor.now
        let gauge = Gauge(report: report, limits: settings.limits, now: now)
        let items = settings.menuBar.displayedItems
        // With both percentages showing, label them so they can't be confused.
        let labelled = items.contains(.percent) && items.contains(.weekPercent)
        let fiveHour = gauge.block == nil ? 0 : gauge.fiveHourPercent
        let weekLevel = Gauge.level(gauge.weekPercent, limits: settings.limits)
        return items.map { item in
            switch item {
            case .gauge: .ring(percent: fiveHour ?? 0, level: gauge.level)
            case .percent: .text((labelled ? "5h " : "") + Gauge.percentText(fiveHour))
            case .weekGauge: .ring(percent: gauge.weekPercent ?? 0, level: weekLevel)
            case .weekPercent: .text((labelled ? "7d " : "") + Gauge.percentText(gauge.weekPercent))
            case .resetTime: .text(gauge.timeToReset(now: now).map(Format.duration) ?? "–")
            case .tokensToday: .text(Format.tokens(report.today.tokens.total))
            case .costToday: .text(report.today.cost == 0 && report.today.costIsPartial ? "—" : Format.cost(report.today.cost))
            }
        }
    }

    /// The title for the status item. Without `textColor`, text and normal rings follow the
    /// menu bar's own color; rings turn orange or red once a threshold is crossed.
    static func attributedTitle(_ parts: [StatusPart], textColor: NSColor? = nil) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let textColor { attributes[.foregroundColor] = textColor }
        let title = NSMutableAttributedString()
        var previous: StatusPart?
        for part in parts {
            if let previous {
                // A ring hugs the reading after it; readings keep a wider gap.
                let gap = if case .ring = previous, case .text = part { " " } else { "  " }
                title.append(NSAttributedString(string: gap, attributes: attributes))
            }
            switch part {
            case .text(let text):
                title.append(NSAttributedString(string: text, attributes: attributes))
            case .ring(let percent, let level):
                let image = ring(percent: percent, level: level, tint: textColor)
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: ((font.capHeight - image.size.height) / 2).rounded(),
                                           width: image.size.width, height: image.size.height)
                let ringString = NSMutableAttributedString(attachment: attachment)
                ringString.addAttributes(attributes, range: NSRange(location: 0, length: ringString.length))
                title.append(ringString)
            }
            previous = part
        }
        return title
    }

    /// A ring filled to `percent`. While normal it takes `tint`, or the label color of
    /// wherever it is drawn; orange or red once a threshold is crossed.
    static func ring(percent: Double, level: Gauge.Level, tint: NSColor? = nil) -> NSImage {
        let side = (font.pointSize + 3).rounded()
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            // Resolved at draw time, so the default follows the menu bar's appearance.
            let color: NSColor = switch level {
            case .normal: tint ?? .labelColor
            case .warning: NSColor(Theme.warning)
            case .critical: NSColor(Theme.critical)
            }
            let lineWidth: CGFloat = 2.2
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = (side - lineWidth) / 2 - 0.5
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            color.withAlphaComponent(0.3).setStroke()
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
        image.accessibilityDescription = "Usage gauge"
        return image
    }

    /// The whole status item as one image, for previews.
    static func render(_ parts: [StatusPart], textColor: NSColor) -> NSImage {
        let title = attributedTitle(parts, textColor: textColor)
        let size = title.size()
        return NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { _ in
            title.draw(at: .zero)
            return true
        }
    }
}

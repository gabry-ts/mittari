import SwiftUI
import MittariCore

/// Capsule filled to a percentage, tinted by level.
struct UsageBar: View {
    let percent: Double?
    var color: Color = Theme.amber
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                if let percent, percent > 0 {
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(proxy.size.width * min(percent, 100) / 100, height))
                }
            }
        }
        .frame(height: height)
    }
}

/// Thin ring gauge with the percentage in the middle.
struct RingGauge: View {
    let percent: Double?
    var color: Color = Theme.amber
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max((percent ?? 0) / 100, 0), 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: Gauge.percentText(percent))
                .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

/// Small "est." tag with an explanation on hover.
struct EstimateBadge: View {
    let mode: LimitMode

    var body: some View {
        Text("est.")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.07), in: .capsule)
            .help(mode.explanation)
    }
}

/// A name with a share bar and its numbers, for models and projects.
struct SliceRow: View {
    let name: String
    let totals: Totals
    let share: Double
    var color: Color = Theme.amber
    var showsCost = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(verbatim: Format.tokens(totals.tokens.total))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if showsCost {
                    CostText(totals: totals)
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
            UsageBar(percent: share * 100, color: color, height: 4)
        }
    }
}

/// A cost, marked when it leaves out usage that has no price.
struct CostText: View {
    let totals: Totals

    var body: some View {
        if totals.cost == 0 && totals.costIsPartial {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .help("No price for this model. Set prices in Settings.")
        } else {
            Text(verbatim: Format.cost(totals.cost) + (totals.costIsPartial ? "+" : ""))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help(totals.costIsPartial ? "Some usage has no price and is left out. Set prices in Settings." : "API list-price equivalent")
        }
    }
}

/// A label over a large value, for summary tiles.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsStore {
    func binding<T>(_ keyPath: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }
}

extension Date {
    /// Clock time in the user's format, e.g. "16:00".
    var clockText: String { formatted(date: .omitted, time: .shortened) }
}

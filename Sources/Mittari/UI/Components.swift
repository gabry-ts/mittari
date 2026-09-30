import MittariCore
import PartitiUI
import SwiftUI

/// Partiti UI's meter filled to a percentage. An empty reading shows the bare track,
/// where the meter alone would still draw a dot.
struct UsageMeter: View {
    let percent: Double?
    var color: Color = MittariStyle.accent.color
    var height: CGFloat = 6

    var body: some View {
        let fraction = min(max((percent ?? 0) / 100, 0), 1)
        Meter(fraction, color: fraction > 0 ? color : .clear, height: height)
    }
}

/// The "est." badge, with an explanation of the reference on hover.
struct EstimateBadge: View {
    let mode: LimitMode

    var body: some View {
        Badge("est.", style: .neutral)
            .help(mode.explanation)
    }
}

/// A name with a share bar and its numbers, for models and projects.
struct SliceRow: View {
    let name: String
    let totals: Totals
    let share: Double
    var color: Color = MittariStyle.accent.color
    /// Dims the name, for a row that sums up the rest.
    var isSummary = false
    var showsCost = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = Ink(colorScheme)
        VStack(spacing: PUI.Space.xs) {
            HStack(spacing: PUI.Space.s) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(verbatim: name)
                    .foregroundStyle(isSummary ? ink.secondary : ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: PUI.Space.m)
                Text(verbatim: Format.tokens(totals.tokens.total))
                    .monospacedDigit()
                    .foregroundStyle(ink.primary)
                if showsCost {
                    CostText(totals: totals)
                        .frame(minWidth: 58, alignment: .trailing)
                }
            }
            .font(PUI.Font.callout)
            Meter(min(max(share, 0), 1), color: color, height: 4)
                .padding(.leading, PUI.Space.l)
        }
    }
}

/// A cost, marked when it leaves out usage that has no price.
struct CostText: View {
    let totals: Totals
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = Ink(colorScheme)
        if totals.cost == 0 && totals.costIsPartial {
            Text(verbatim: "—")
                .foregroundStyle(ink.secondary)
                .help("No price for this model. Set prices in Settings.")
        } else {
            Text(verbatim: Format.costText(totals))
                .monospacedDigit()
                .foregroundStyle(ink.secondary)
                .help(totals.costIsPartial ? "Some usage has no price and is left out. Set prices in Settings." : "API list-price equivalent")
        }
    }
}

extension Format {
    /// A cost with a "+" when some usage has no price, or a dash when none of it has one.
    static func costText(_ totals: Totals) -> String {
        if totals.cost == 0 && totals.costIsPartial { return "—" }
        return cost(totals.cost) + (totals.costIsPartial ? "+" : "")
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

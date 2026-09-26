import Foundation

/// Compact, locale-neutral text for numbers shown in tight spaces.
public enum Format {
    /// 950, 12.3K, 4.5M, 1.2B.
    public static func tokens(_ value: Int) -> String {
        let v = Double(value)
        switch abs(v) {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return trim(v / 1_000) + "K"
        case ..<1_000_000_000: return trim(v / 1_000_000) + "M"
        default: return trim(v / 1_000_000_000) + "B"
        }
    }

    /// $0.42, $12.30, $1,234; nil prints as a dash.
    public static func cost(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 1000 { return "$" + Int(value.rounded()).formatted(.number.locale(Locale(identifier: "en_US"))) }
        return String(format: "$%.2f", value)
    }

    /// 1h 48m, 12m, <1m.
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 1 { return "<1m" }
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func trim(_ v: Double) -> String {
        let s = v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

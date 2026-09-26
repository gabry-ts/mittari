import Foundation

/// Parses the ISO 8601 timestamps found in Claude Code and Codex logs. The common
/// `2026-09-22T14:05:11.653Z` shape is parsed by hand, since it appears on every line
/// and a formatter is far slower; anything else goes through Foundation.
public enum Timestamp {
    public static func parse(_ string: String) -> Date? {
        var s = string
        return s.withUTF8 { fast($0) } ?? (try? Date(string, strategy: fractional)) ?? (try? Date(string, strategy: .iso8601))
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static func fast(_ b: UnsafeBufferPointer<UInt8>) -> Date? {
        // yyyy-MM-ddTHH:mm:ss[.fff…]Z
        guard b.count >= 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58, b[b.count - 1] == 90 else {
            return nil
        }
        func num(_ from: Int, _ len: Int) -> Int? {
            var value = 0
            for i in from..<from + len {
                let d = Int(b[i]) - 48
                guard d >= 0, d <= 9 else { return nil }
                value = value * 10 + d
            }
            return value
        }
        guard let year = num(0, 4), let month = num(5, 2), let day = num(8, 2),
              let hour = num(11, 2), let minute = num(14, 2), let second = num(17, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var fraction = 0.0
        if b.count > 20 {
            guard b[19] == 46 else { return nil }
            var scale = 0.1
            for i in 20..<(b.count - 1) {
                let d = Int(b[i]) - 48
                guard d >= 0, d <= 9 else { return nil }
                fraction += Double(d) * scale
                scale /= 10
            }
        } else if b[19] != 90 {
            return nil
        }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

import Foundation
import MittariCore
import UserNotifications

/// Posts a notification when the current 5-hour window crosses the warning or critical
/// threshold, once per window and level. Levels already crossed when Mittari starts are
/// not announced.
@MainActor
final class Notifier {
    private var announced: Set<String> = []
    private var isPrimed = false
    private var didRequestAuthorization = false

    func check(gauge: Gauge, limits: LimitSettings) {
        guard let block = gauge.block, gauge.level > .normal else {
            isPrimed = true
            return
        }
        let key = "\(block.start.timeIntervalSince1970)-\(gauge.level.rawValue)"
        guard !announced.contains(key) else { return }
        announced.insert(key)
        // Crossing warning and critical in one refresh only needs the critical message.
        if gauge.level == .critical { announced.insert("\(block.start.timeIntervalSince1970)-\(Gauge.Level.warning.rawValue)") }
        guard isPrimed, limits.notify else {
            isPrimed = true
            return
        }
        let percent = Gauge.percentText(gauge.fiveHourPercent)
        let reset = block.end.formatted(date: .omitted, time: .shortened)
        post(
            title: gauge.level == .critical ? "Claude Code window at \(percent)" : "Claude Code window past \(Int(limits.warningPercent))%",
            body: "Estimated \(percent) of your 5-hour limit. The window resets at \(reset)."
        )
    }

    func requestAuthorization() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func post(title: String, body: String) {
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

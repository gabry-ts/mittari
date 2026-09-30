import Foundation
import Observation
import Sparkle

/// Thin wrapper over Sparkle's standard updater controller, created once and shared.
/// Sparkle asks the user on the second launch whether to check automatically, and
/// otherwise follows its own default behaviour for downloading and installing updates.
@MainActor
enum Updater {
    /// The offscreen render harnesses build ordinary views, including the About pane,
    /// with sample data and no real app delegate; starting Sparkle there would reach the
    /// network and could show its own permission alert, so it stays unstarted then.
    private static var isRenderHarness: Bool {
        let args = CommandLine.arguments
        return args.contains("--render-snapshots") || args.contains("--render-icon")
    }

    static let controller = SPUStandardUpdaterController(
        startingUpdater: !isRenderHarness, updaterDelegate: nil, userDriverDelegate: nil
    )

    static var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Whether a check can start now, for the views that offer one.
    static let availability = UpdateAvailability(updater: isRenderHarness ? nil : controller.updater)
}

/// Follows Sparkle's `canCheckForUpdates`, which is false while a check is running.
/// Without an updater, as in the render harnesses, a check always reads as possible.
@MainActor
@Observable
final class UpdateAvailability {
    private(set) var canCheckForUpdates = true
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater?) {
        observation = updater?.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }
}

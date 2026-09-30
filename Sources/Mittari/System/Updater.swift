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
}

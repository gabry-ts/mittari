import Sparkle

/// Thin wrapper over Sparkle's standard updater controller, created once and shared.
/// Sparkle asks the user on the second launch whether to check automatically, and
/// otherwise follows its own default behaviour for downloading and installing updates.
@MainActor
enum Updater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    static var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

import AppKit

/// Links opened outside the app, kept in one place.
enum ExternalLinks {
    static func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/gabrielepartiti")!)
    }
}

import AppKit
import Observation
import SwiftUI

/// The menu bar item and its popover. Managed directly instead of through MenuBarExtra,
/// which does not reliably redraw its label, so live readings update on every change.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let makeContent: () -> AnyView
    private let render: () -> [StatusPart]
    private var shown: [StatusPart]?

    /// The popover's view is built on open and dropped on close, so nothing in it keeps
    /// animating while it's hidden.
    init(content: @escaping () -> AnyView, render: @escaping () -> [StatusPart]) {
        self.makeContent = content
        self.render = render
        super.init()
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        item.button?.target = self
        item.button?.action = #selector(toggle)
        refresh()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    /// Draws the title and re-arms tracking, so any change to what it reads (settings,
    /// readings) triggers the next draw.
    private func refresh() {
        let content = withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        guard let button = item.button else { return }
        // Rebuilding the title only when it changes avoids needless relayout.
        guard content != shown else { return }
        shown = content
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = StatusImage.attributedTitle(content)
        button.setAccessibilityLabel("Mittari")
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            let host = NSHostingController(rootView: makeContent())
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}

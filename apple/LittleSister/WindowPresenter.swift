//
//  WindowPresenter.swift
//  LittleSister
//

import AppKit
import SwiftUI

// Owns the app's two secondary windows — Settings and Debug Log — as plain
// AppKit windows, created and ordered front directly.
//
// They used to be SwiftUI scenes reached indirectly: a menu action posted a
// NotificationCenter message, and a 1x1 "Hidden" window scene received it and
// called openSettings()/openWindow(id:). That chain broke silently whenever the
// app was launched at login — an LSUIElement app started by launchd is never
// activated, so SwiftUI never presented the Hidden window, its view was never
// instantiated, and with no subscriber the notifications reached nobody. Both
// menu items did nothing at all, with no error anywhere. See ADR-0008 and
// docs/platform-notes.md.
//
// AppKit window ordering depends on neither scene presentation nor app
// activation, so the menu items now work in every launch mode.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private let viewModel: MonitoringViewModel
    private var settingsWindow: NSWindow?
    private var debugLogWindow: NSWindow?

    init(viewModel: MonitoringViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    // MARK: - Presenting

    func showSettings() {
        if let open = settingsWindow, open.isVisible {
            present(open, label: "Settings")
            return
        }
        // A closed window is rebuilt rather than reused, so SwiftUI re-runs
        // SettingsView.onAppear and the form reloads from truth on every open
        // (ADR-0004) instead of showing whatever was typed and then cancelled.
        let window = makeWindow(title: "Little Sister Settings",
                                content: SettingsView(viewModel: viewModel),
                                resizable: false)
        settingsWindow = window
        present(window, label: "Settings")
    }

    func showDebugLog() {
        if let open = debugLogWindow, open.isVisible {
            present(open, label: "Debug Log")
            return
        }
        let window = makeWindow(title: "Debug Log",
                                content: DebugLogView(),
                                resizable: true,
                                defaultSize: NSSize(width: 780, height: 480),
                                autosaveName: "DebugLogWindow")
        debugLogWindow = window
        present(window, label: "Debug Log")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        DebugLog.shared.record("Window closed: \(label(for: closing))", category: .menu)
        // Drop back to accessory only once no managed window is left on screen —
        // closing one of two open windows must not take the other's Dock icon
        // (and its ability to come forward) away with it.
        let anotherIsOpen = [settingsWindow, debugLogWindow]
            .compactMap { $0 }
            .contains { $0 !== closing && $0.isVisible }
        if !anotherIsOpen {
            NSApp.setActivationPolicy(.accessory)
            DebugLog.shared.record("Activation policy: accessory", category: .menu)
        }
    }

    // MARK: - Private

    private func makeWindow(title: String,
                            content: some View,
                            resizable: Bool,
                            defaultSize: NSSize? = nil,
                            autosaveName: NSWindow.FrameAutosaveName? = nil) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        if !resizable {
            // Let the window track the SwiftUI content's own size — the Settings
            // form grows and shrinks as its toggles reveal and hide rows.
            hosting.sizingOptions = [.preferredContentSize]
        }
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable]
        // This class holds the reference; letting AppKit release the window on
        // close would leave the stored property dangling.
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let defaultSize {
            window.setContentSize(defaultSize)
        } else if resizable {
            window.setContentSize(hosting.view.fittingSize)
        }
        // Windows are rebuilt on every open, so without an autosaved frame a
        // resizable window would forget the size the user gave it each time.
        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
            if !window.setFrameUsingName(autosaveName) { window.center() }
        } else {
            window.center()
        }
        return window
    }

    private func present(_ window: NSWindow, label: String) {
        // Only a real transition earns a line: re-selecting the menu item while a
        // window is already open changes nothing, and saying so would make every
        // policy entry in the log meaningless.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            DebugLog.shared.record("Activation policy: regular", category: .menu)
        }
        // An app that has just become .regular needs a moment before it can take
        // activation; activating in the same turn of the run loop is unreliable.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            DebugLog.shared.record("Window shown: \(label)", category: .menu)
        }
    }

    private func label(for window: NSWindow) -> String {
        if window === settingsWindow { return "Settings" }
        if window === debugLogWindow { return "Debug Log" }
        return window.title
    }
}

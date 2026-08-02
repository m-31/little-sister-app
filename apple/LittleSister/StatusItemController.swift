//
//  StatusItemController.swift
//  LittleSister
//

import AppKit
import Observation

private let menuTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

private let menuDateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, HH:mm:ss"
    return f
}()

private extension Date {
    // Time alone for today, date and time otherwise: a bare "19:16:53" on a
    // timestamp from another day reads as this morning.
    //
    // Server timestamps arrive as RFC 3339 with an explicit offset and decode to
    // an absolute instant, and neither formatter sets a `timeZone` — so both
    // render in this Mac's zone regardless of which zone the server runs in.
    var menuStamp: String {
        Calendar.current.isDateInToday(self)
            ? menuTimeFormatter.string(from: self)
            : menuDateTimeFormatter.string(from: self)
    }
}

// Returns the "Observed:" menu line, or nil when it carries no information.
// Three rules (ADR-0009, updated 2026-07-30):
//   stamp present           → "Observed: <time>" [+ "  (stale)" when stale]
//   no stamp, stale         → "Observed: —  (stale)"
//   no stamp, not stale     → nil (e.g. healthy multi-check root)
func observedLine(timestamp: Date?, stale: Bool) -> String? {
    let staleSuffix = stale ? "  (stale)" : ""
    if let ts = timestamp {
        return "Observed: \(ts.menuStamp)\(staleSuffix)"
    }
    return stale ? "Observed: —\(staleSuffix)" : nil
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let viewModel: MonitoringViewModel
    private let windows: WindowPresenter

    init(viewModel: MonitoringViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.menu = NSMenu()
        self.windows = WindowPresenter(viewModel: viewModel)
        super.init()

        menu.delegate = self
        statusItem.menu = menu

        updateIcon()
        observeViewModel()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        DebugLog.shared.record("Menu opened: \(viewModel.displayState.label)", category: .menu)
        menu.removeAllItems()

        // 1. Header
        let header = NSMenuItem(title: "Monitoring: \(viewModel.displayState.label)", action: nil, keyEquivalent: "")
        header.image = NSImage(systemSymbolName: viewModel.displayState.symbol, accessibilityDescription: nil)
        menu.addItem(header)

        // 2. Target
        menu.addItem(NSMenuItem(title: "Target: \(viewModel.targetDisplay)", action: nil, keyEquivalent: ""))

        // 3. Detail section — the reason line, then the shared timestamp block.
        //
        // Only the reason varies by state: a client-side failure has no response
        // to read reasons from, and a healthy node's reasons get their own
        // section below. The timestamps are identical everywhere (ADR-0009).
        switch viewModel.displayState {
        case .healthy:
            break
        case .undefined(let reason), .unavailable(let reason):
            menu.addItem(NSMenuItem(title: "Reason: \(reason)", action: nil, keyEquivalent: ""))
        default:
            if let reason = viewModel.lastResponse?.status.reasons.first {
                menu.addItem(NSMenuItem(title: "Reason: \(reason)", action: nil, keyEquivalent: ""))
            }
        }

        // 3.5. Waiting for network — only while URLSession is holding the
        // current request open because the path is not viable yet. It explains
        // the two lines below it rather than replacing them: during a wait the
        // state line still shows the last answer the server gave and "Last
        // request" stops advancing, which is exactly what an app that has
        // silently stopped polling looks like (ADR-0011 §3).
        if viewModel.isWaitingForNetwork {
            menu.addItem(NSMenuItem(title: "Waiting for network…", action: nil, keyEquivalent: ""))
        }

        appendTimestamps(to: menu)

        // 4. Separator
        menu.addItem(.separator())

        // 5. Reasons section (only when healthy) — mirrors MenuView.reasonsSection
        if case .healthy = viewModel.displayState {
            let reasons = viewModel.lastResponse?.status.reasons ?? []
            if reasons.isEmpty {
                menu.addItem(NSMenuItem(title: "No active reasons", action: nil, keyEquivalent: ""))
            } else {
                for reason in reasons {
                    menu.addItem(NSMenuItem(title: reason, action: nil, keyEquivalent: ""))
                }
            }
            menu.addItem(.separator())
        }

        // 5.5. Acknowledge alarm — only while the repeating alarm is actually playing
        if viewModel.isAlarmActive {
            let acknowledge = NSMenuItem(title: "Acknowledge Alarm", action: #selector(acknowledgeAlarm), keyEquivalent: "")
            acknowledge.target = self
            menu.addItem(acknowledge)
            menu.addItem(.separator())
        }

        // 6. Action items
        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        let dashboard = NSMenuItem(title: "Open dashboard", action: #selector(openDashboard), keyEquivalent: "")
        dashboard.target = self
        menu.addItem(dashboard)

        let debugLog = NSMenuItem(title: "View Debug Log…", action: #selector(openDebugLog), keyEquivalent: "")
        debugLog.target = self
        menu.addItem(debugLog)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        // 7. Separator
        menu.addItem(.separator())

        // 8. Quit — standard AppKit pattern: target NSApp directly
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    // The timestamps shown in the menu (ADR-0009):
    //
    //   Observed        — observedLine(timestamp:stale:): present only where the
    //                     server has a single answer (leaf or single-check
    //                     container). nil+stale → dash line. nil+not-stale → absent.
    //   Server snapshot — `generated_at`: the serving instance's clock when it
    //                     built this response. Omitted when it renders exactly
    //                     like "Last request" — see below.
    //   Last request    — this app's clock when it sent its last poll. Set
    //                     *before* the request, so it legitimately precedes the
    //                     server's snapshot rather than following it.
    //
    // `lastResponse` survives a failed poll, so while unavailable the first two
    // describe the last response that did arrive — exactly the question worth
    // answering then — while "Last request" keeps ticking, so a stalled polling
    // loop is visible as an old value there rather than being indistinguishable
    // from stale server data.
    private func appendTimestamps(to menu: NSMenu) {
        let requestStamp = viewModel.lastChecked.map(\.menuStamp)
        if let r = viewModel.lastResponse {
            if let line = observedLine(timestamp: r.status.timestamp, stale: r.status.stale) {
                menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
            }
            // On a fast link the server builds its snapshot within the same
            // second the request was sent, so this line would repeat the next one
            // verbatim. The test is literally "would these two read the same?" —
            // no threshold to invent, and the line comes back on its own as soon
            // as the two clocks disagree: a slow server, skew between the two
            // machines, or a federated branch answered from an older snapshot.
            let snapshotStamp = r.generatedAt.menuStamp
            if snapshotStamp != requestStamp {
                menu.addItem(NSMenuItem(title: "Server snapshot: \(snapshotStamp)",
                                        action: nil, keyEquivalent: ""))
            }
        }
        if let requestStamp {
            menu.addItem(NSMenuItem(title: "Last request: \(requestStamp)",
                                    action: nil, keyEquivalent: ""))
        }
        // Only when the client itself can't reach the server: the two server
        // lines above are then frozen at the last success, and how long ago that
        // was is the thing worth knowing. `.undefined` needs no such line — the
        // server answered, it just answered UNDEFINED.
        if case .unavailable = viewModel.displayState, let ok = viewModel.lastSucceeded {
            menu.addItem(NSMenuItem(title: "Last success: \(ok.menuStamp)",
                                    action: nil, keyEquivalent: ""))
        }
    }

    // MARK: - Menu actions

    @objc private func acknowledgeAlarm() {
        DebugLog.shared.record("Menu: Acknowledge Alarm", category: .menu)
        viewModel.acknowledgeAlarm()
    }

    @objc private func refreshNow() {
        DebugLog.shared.record("Menu: Refresh now", category: .menu)
        viewModel.manualRefresh()
    }

    @objc private func openDashboard() {
        let url = AppSettings().dashboardURL
        DebugLog.shared.record("Menu: Open dashboard (\(url))", category: .menu)
        NSWorkspace.shared.open(url)
    }

    @objc private func openDebugLog() {
        DebugLog.shared.record("Menu: View Debug Log…", category: .menu)
        windows.showDebugLog()
    }

    @objc private func openSettings() {
        DebugLog.shared.record("Menu: Settings…", category: .menu)
        windows.showSettings()
    }

    // MARK: - Icon

    private let iconSizeConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular, scale: .medium)
    private var blinkTask: Task<Void, Never>?
    private var blinkBright = true

    private func updateIcon() {
        if case .error = viewModel.displayState {
            startBlinkingIfNeeded()
        } else {
            stopBlinking()
            guard let base = NSImage(systemSymbolName: viewModel.displayState.symbol,
                                     accessibilityDescription: viewModel.displayState.label) else { return }
            base.isTemplate = true
            statusItem.button?.image = base.withSymbolConfiguration(iconSizeConfig) ?? base
        }
    }

    private func startBlinkingIfNeeded() {
        guard blinkTask == nil else { return }
        blinkTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.applyAlertFrame(bright: self.blinkBright)
                self.blinkBright.toggle()
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func stopBlinking() {
        blinkTask?.cancel()
        blinkTask = nil
        blinkBright = true
    }

    private func applyAlertFrame(bright: Bool) {
        guard let base = NSImage(systemSymbolName: viewModel.displayState.symbol,
                                 accessibilityDescription: viewModel.displayState.label) else { return }
        let red: NSColor = bright ? .systemRed : .systemRed.withAlphaComponent(0.35)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white, red])
        let combined = iconSizeConfig.applying(colorConfig)
        if let colored = base.withSymbolConfiguration(combined) {
            colored.isTemplate = false
            statusItem.button?.image = colored
        }
    }

    // Bridges @Observable changes into this non-SwiftUI context. withObservationTracking
    // fires once per change and must be re-registered inside its own onChange closure to
    // keep observing — the standard pattern for observing outside a view body.
    private func observeViewModel() {
        withObservationTracking {
            _ = viewModel.displayState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.observeViewModel()
            }
        }
    }
}

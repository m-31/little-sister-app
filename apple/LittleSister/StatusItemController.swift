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

private extension Date {
    var menuShortTime: String { menuTimeFormatter.string(from: self) }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let viewModel: MonitoringViewModel

    init(viewModel: MonitoringViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.menu = NSMenu()
        super.init()

        menu.delegate = self
        statusItem.menu = menu

        updateIcon()
        observeViewModel()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Header
        let header = NSMenuItem(title: "Monitoring: \(viewModel.displayState.label)", action: nil, keyEquivalent: "")
        header.image = NSImage(systemSymbolName: viewModel.displayState.symbol, accessibilityDescription: nil)
        menu.addItem(header)

        // 2. Target
        menu.addItem(NSMenuItem(title: "Target: \(viewModel.targetDisplay)", action: nil, keyEquivalent: ""))

        // 3. Detail section — mirrors MenuView.detailSection exactly
        switch viewModel.displayState {
        case .healthy:
            if let r = viewModel.lastResponse {
                menu.addItem(NSMenuItem(title: "Server snapshot: \(r.generatedAt.menuShortTime)", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "Node observed: \(r.status.timestamp.menuShortTime)", action: nil, keyEquivalent: ""))
            }
            if let checked = viewModel.lastChecked {
                menu.addItem(NSMenuItem(title: "Last request: \(checked.menuShortTime)", action: nil, keyEquivalent: ""))
            }
        case .undefined(let reason), .unavailable(let reason):
            menu.addItem(NSMenuItem(title: "Reason: \(reason)", action: nil, keyEquivalent: ""))
            if let checked = viewModel.lastChecked {
                menu.addItem(NSMenuItem(title: "Last attempt: \(checked.menuShortTime)", action: nil, keyEquivalent: ""))
            }
        default:
            if let reason = viewModel.lastResponse?.status.reasons.first {
                menu.addItem(NSMenuItem(title: "Reason: \(reason)", action: nil, keyEquivalent: ""))
            }
            if let r = viewModel.lastResponse {
                menu.addItem(NSMenuItem(title: "Updated: \(r.status.timestamp.menuShortTime)", action: nil, keyEquivalent: ""))
            }
        }

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

    // MARK: - Menu actions

    @objc private func acknowledgeAlarm() { viewModel.acknowledgeAlarm() }

    @objc private func refreshNow() { viewModel.manualRefresh() }

    @objc private func openDashboard() { NSWorkspace.shared.open(AppSettings().dashboardURL) }

    @objc private func openDebugLog() {
        NotificationCenter.default.post(name: .openDebugLogRequest, object: nil)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
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

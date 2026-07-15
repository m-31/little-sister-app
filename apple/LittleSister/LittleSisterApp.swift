//
//  LittleSisterApp.swift
//  LittleSister
//
//  Created by Michael Meyling on 2026-07-01.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
    static let settingsWindowClosed = Notification.Name("settingsWindowClosed")
    static let openDebugLogRequest = Notification.Name("openDebugLogRequest")
    static let debugLogWindowClosed = Notification.Name("debugLogWindowClosed")
}

struct HiddenWindowView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    NSApp.setActivationPolicy(.regular)
                    try? await Task.sleep(for: .milliseconds(100))
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                    try? await Task.sleep(for: .milliseconds(200))
                    if let win = NSApp.windows.first(where: {
                        $0.title.localizedCaseInsensitiveContains("settings") ||
                        $0.title.localizedCaseInsensitiveContains("little sister")
                    }) {
                        win.makeKeyAndOrderFront(nil)
                        win.orderFrontRegardless()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowClosed)) { _ in
                NSApp.setActivationPolicy(.accessory)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDebugLogRequest)) { _ in
                Task { @MainActor in
                    NSApp.setActivationPolicy(.regular)
                    try? await Task.sleep(for: .milliseconds(100))
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "DebugLog")
                    try? await Task.sleep(for: .milliseconds(200))
                    if let win = NSApp.windows.first(where: {
                        $0.title.localizedCaseInsensitiveContains("debug log")
                    }) {
                        win.makeKeyAndOrderFront(nil)
                        win.orderFrontRegardless()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .debugLogWindowClosed)) { _ in
                NSApp.setActivationPolicy(.accessory)
            }
    }
}

@main
struct LittleSisterApp: App {
    @State private var viewModel: MonitoringViewModel
    @State private var statusItemController: StatusItemController

    @MainActor
    init() {
        let settings = AppSettings()
        let vm = MonitoringViewModel(
            clientProvider: {
                let s = AppSettings()
                let t = KeychainTokenStore().loadToken() ?? ""
                let config = URLSessionConfiguration.default
                config.waitsForConnectivity = true
                config.timeoutIntervalForResource = 30
                let session = URLSession(configuration: config)
                return StatusAPIClient(baseURL: s.baseURL, nodePath: s.nodePath, token: t, session: session)
            },
            notificationSender: LiveNotificationSender(),
            pollInterval: settings.pollInterval,
            nodePath: settings.nodePath
        )
        _viewModel = State(wrappedValue: vm)
        vm.startPolling()
        DebugLog.shared.record("App launched", category: .lifecycle)
        _statusItemController = State(wrappedValue: StatusItemController(viewModel: vm))
    }

    var body: some Scene {
        Window("Hidden", id: "HiddenWindow") {
            HiddenWindowView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)

        Window("Debug Log", id: "DebugLog") {
            DebugLogView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
    }
}

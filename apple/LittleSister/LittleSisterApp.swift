//
//  LittleSisterApp.swift
//  LittleSister
//
//  Created by Michael Meyling on 2026-07-01.
//

import Foundation
import SwiftUI

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
                // A fresh session per poll, with both timeouts derived from the
                // current poll interval (ADR-0011 §2). What that means for a
                // URLSession lives in StatusAPIClient, not here.
                let session = StatusAPIClient.makeSession(pollInterval: s.pollInterval)
                return StatusAPIClient(baseURL: s.baseURL, nodePath: s.nodePath, token: t, session: session)
            },
            notificationSender: LiveNotificationSender(),
            intervalProvider: { AppSettings().pollInterval },
            nodePath: settings.nodePath
        )
        _viewModel = State(wrappedValue: vm)
        vm.startPolling()
        DebugLog.shared.record("App launched", category: .lifecycle)
        _statusItemController = State(wrappedValue: StatusItemController(viewModel: vm))
    }

    // The App protocol requires at least one scene, but this app presents no
    // SwiftUI scene at all: the menu bar item is an NSStatusItem (ADR-0001) and
    // the Settings/Debug Log windows are AppKit windows owned by
    // WindowPresenter (ADR-0008). `Settings` serves as the placeholder because,
    // unlike `Window`, it never auto-presents at launch — and with LSUIElement
    // there is no app menu to reach it from either.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

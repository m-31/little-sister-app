//
//  MonitoringViewModel.swift
//  LittleSister
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class MonitoringViewModel {

    // MARK: - Observable state (read by views)

    var displayState: DisplayState = .unavailable(reason: "Starting…")
    var lastChecked: Date?
    var lastSucceeded: Date?
    var lastResponse: StatusResponse?

    // MARK: - Non-observed internal state

    // Holds the result of the previous poll so notification(from:to:) can compare
    // transitions. Nil until the first poll completes; set to newState (not the
    // pre-poll value) so it serves as the correct "from" for the next poll.
    @ObservationIgnored private(set) var previousDisplayState: DisplayState?

    // The configured subtree path (e.g. "system/db"), or nil for the root.
    // Presentational — owned here so the menu can show "Target: /system/db"
    // without reaching into StatusAPIClient's internal URL.
    let configuredNodePath: String?

    // Formatted target string ready for display: "/system/db" or "/status".
    var targetDisplay: String {
        if let path = configuredNodePath, !path.isEmpty {
            return "/\(path)"
        }
        return "/status"
    }

    // Observable so the menu-bar icon can switch to arrow.clockwise while a poll is in flight.
    // Also serves as the overlap guard — poll() returns early when true.
    private(set) var isRefreshing = false
    private(set) var isAlarmActive = false
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var alarmLoopTask: Task<Void, Never>?
    @ObservationIgnored private let clientProvider: () -> StatusAPIClient
    @ObservationIgnored private let notificationSender: any NotificationSending
    @ObservationIgnored private let pollInterval: Int

    // MARK: - Init

    init(
        clientProvider: @escaping () -> StatusAPIClient,
        notificationSender: any NotificationSending,
        pollInterval: Int = 60,
        nodePath: String? = nil
    ) {
        self.clientProvider = clientProvider
        self.notificationSender = notificationSender
        self.pollInterval = max(5, pollInterval)
        self.configuredNodePath = nodePath
    }

    // MARK: - Public interface

    func startPolling() {
        // Request authorization once at launch; non-blocking, silent on denial.
        Task { await notificationSender.requestAuthorization() }
        pollingTask?.cancel()
        pollingTask = Task {
            await poll()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard !Task.isCancelled else { break }
                await poll()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        stopAlarm()
    }

    // Called from synchronous SwiftUI action handlers.  Does not reset the
    // timer — the background loop keeps its own schedule regardless.
    func manualRefresh() {
        Task { await poll() }
    }

    // MARK: - Private

    // Internal (not private) so tests can drive state transitions directly.
    func poll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastChecked = Date()
        let client = clientProvider()
        do {
            let response = try await client.fetchStatus()
            lastResponse = response
            lastSucceeded = Date()
            let newState = LittleSister.displayState(for: response.status)
            DebugLog.shared.record("Poll: \(newState.label)", category: .poll)
            await applyState(newState)
        } catch let error as APIError {
            let reason = errorReason(from: error)
            DebugLog.shared.record("Poll failed: \(reason)", category: .poll)
            await applyState(.unavailable(reason: reason))
        } catch {
            // fetchStatus only throws APIError; this branch is unreachable in practice.
        }
    }

    private func applyState(_ newState: DisplayState) async {
        let from = previousDisplayState
        let isStartup = from == nil
        displayState = newState
        previousDisplayState = newState   // becomes "from" for the next poll's comparison
        if let from, !from.isSameCase(as: newState) {
            DebugLog.shared.record("State: \(from.label) → \(newState.label)", category: .lifecycle)
        }

        let note: (title: String, body: String)?
        if isStartup {
            note = ("Little Sister started", "Current status: \(newState.label)")
        } else {
            note = LittleSister.notification(from: from, to: newState)
        }

        if let note {
            let isErrorTransition = newState.isSameCase(as: .error)
            await notificationSender.send(
                title: note.title,
                body: note.body,
                isAlert: isErrorTransition && AppSettings().soundOnError
            )
            if isErrorTransition && AppSettings().soundOnError {
                startAlarm()
            }
            DebugLog.shared.record("Notification: \(note.title)", category: .notification)
            if isErrorTransition, AppSettings().modalAlertOnError {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    showErrorAlertDialog(
                        title: note.title,
                        message: self.lastResponse?.status.reasons.first ?? note.body,
                        onAcknowledge: { [weak self] in self?.acknowledgeAlarm() }
                    )
                }
            }
        }

        if !newState.isSameCase(as: .error) {
            stopAlarm()
        }
    }

    private func errorReason(from error: APIError) -> String {
        switch error {
        case .networkUnavailable:
            return "Network unavailable"
        case .timeout:
            return "Request timed out"
        case .unauthorized(let detail):
            return detail ?? "Unauthorized"
        case .notFound(let detail):
            return detail ?? "Node path not found"
        case .serverError(let code, let detail):
            return detail ?? "Server error (\(code))"
        case .invalidResponse:
            return "Invalid response"
        case .unsupportedSchemaVersion(let v):
            return "Unsupported schema version \(v)"
        }
    }

    // MARK: - Alarm sound

    private func startAlarm() {
        let duration = playCurrentAlarmSound()
        isAlarmActive = true
        guard AppSettings().repeatAlarmSound else { return }
        guard alarmLoopTask == nil else { return }   // already looping from an earlier transition
        alarmLoopTask = Task { [weak self] in
            var nextDelay = Self.repeatInterval(afterPlaying: duration)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(nextDelay))
                guard !Task.isCancelled, let self else { break }
                let playedDuration = self.playCurrentAlarmSound()
                nextDelay = Self.repeatInterval(afterPlaying: playedDuration)
            }
        }
    }

    // Never starts the next repeat before the current sound has actually
    // finished, plus a short gap so consecutive plays don't run together.
    // Floored at 5s so short sounds keep the original cadence.
    private static func repeatInterval(afterPlaying duration: TimeInterval) -> TimeInterval {
        let gap = 1.0
        let minimumInterval = 5.0
        guard duration.isFinite, duration > 0 else { return minimumInterval }
        return max(duration + gap, minimumInterval)
    }

    private func stopAlarm() {
        alarmLoopTask?.cancel()
        alarmLoopTask = nil
        isAlarmActive = false
    }

    func acknowledgeAlarm() {
        stopAlarm()
    }

    @discardableResult
    private func playCurrentAlarmSound() -> TimeInterval {
        let settings = AppSettings()
        if settings.useCustomAlarmSound, let path = settings.customAlarmSoundPath {
            return notificationSender.playAlarm(fileURL: URL(fileURLWithPath: path))
        } else {
            return notificationSender.playAlarm(soundName: settings.alarmSoundName)
        }
    }
}

// runModal() blocks the calling thread, so this must only be called from inside a
// detached Task to avoid stalling the polling loop while the user reads the dialog.
@MainActor
private func showErrorAlertDialog(title: String, message: String, onAcknowledge: @escaping () -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning   // .critical auto-badges .icon with a system caution triangle
    alert.icon = NSImage(named: "AlertIcon")
    alert.addButton(withTitle: "Acknowledge")
    NSApp.activate(ignoringOtherApps: true)
    alert.window.level = .floating
    alert.window.makeKeyAndOrderFront(nil)
    alert.runModal()
    onAcknowledge()
}

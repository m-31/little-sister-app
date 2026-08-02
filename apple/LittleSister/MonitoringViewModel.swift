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
    // True while URLSession is holding the current request because the network
    // path is not viable yet. Presentational only — see `noteWaitingForNetwork`.
    private(set) var isWaitingForNetwork = false
    // Consecutive failed polls, driving the shortened retry schedule below.
    @ObservationIgnored private var consecutiveFailures = 0
    // The class of the most recent failure, which decides *which* schedule the
    // count above is fed to (ADR-0011 §4). Written on every failing poll and
    // read only while `consecutiveFailures > 0`, so it is never read stale; the
    // initial value is what an unused schedule would ask for anyway.
    @ObservationIgnored private var lastFailureClass: RetryClass = .transient
    // Identifies the poll now in flight, so a wait callback that arrives after
    // its own request finished cannot raise a flag nobody will lower. The
    // sequence only ever counts up; `inFlightPoll` is nil whenever no poll is
    // running, which is the state in which no callback may be believed.
    //
    // `inFlightPoll` is internal, not private, so tests can name the token the
    // running poll would have handed out.
    @ObservationIgnored private var pollSequence = 0
    @ObservationIgnored private(set) var inFlightPoll: Int?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var alarmLoopTask: Task<Void, Never>?
    @ObservationIgnored private let clientProvider: () -> StatusAPIClient
    @ObservationIgnored private let notificationSender: any NotificationSending
    // The configured cadence, re-read on every use rather than captured at
    // init. Two things now derive from it — this loop's schedule and the
    // session's timeout budget (ADR-0011 §2) — and the timeouts are built fresh
    // for every poll from the current `AppSettings`. A value captured here would
    // leave the loop on the old interval until the next launch while the
    // timeouts already followed the new one, which is worse than both being
    // stale together.
    //
    // The two reads are not atomic, and needn't be: the loop reads the interval
    // at the top of an iteration, the client provider reads `AppSettings` again
    // when the poll actually runs, up to an interval later. Committing Settings
    // in between gives exactly one poll whose budget comes from the new interval
    // after a sleep that used the old — self-correcting on the next iteration,
    // and harmless, since each value is internally consistent and the budget is
    // below whichever interval produced it.
    @ObservationIgnored private let intervalProvider: () -> Int

    // MARK: - Init

    init(
        clientProvider: @escaping () -> StatusAPIClient,
        notificationSender: any NotificationSending,
        intervalProvider: @escaping () -> Int = { AppSettings.defaultPollInterval },
        nodePath: String? = nil
    ) {
        self.clientProvider = clientProvider
        self.notificationSender = notificationSender
        self.intervalProvider = intervalProvider
        self.configuredNodePath = nodePath
    }

    // MARK: - Public interface

    func startPolling() {
        // Request authorization once at launch; non-blocking, silent on denial.
        Task { await notificationSender.requestAuthorization() }
        pollingTask?.cancel()
        consecutiveFailures = 0
        pollingTask = Task {
            await poll()
            while !Task.isCancelled {
                // Decided here rather than inside poll(), so the logged delay is
                // the one this loop will actually wait — a manual refresh does
                // not reschedule it. The interval is read once per iteration so
                // the delay and the comparison below cannot straddle a change.
                let interval = currentPollInterval
                let delay = Self.retryDelay(
                    consecutiveFailures: consecutiveFailures,
                    pollInterval: interval,
                    retryClass: lastFailureClass)
                if delay != interval {
                    // The class is named because it is the only thing that
                    // explains the delay: after one failure the same count
                    // yields 5s transient and 60s definite, and a log line
                    // reporting the slower of those without saying why reads
                    // like the app has stalled.
                    let failureClass = switch lastFailureClass {
                    case .definite: "definite"
                    case .transient: "transient"
                    }
                    DebugLog.shared.record(
                        "Retrying in \(delay)s (\(failureClass) failure, "
                            + "\(consecutiveFailures) consecutive)",
                        category: .poll)
                }
                try? await Task.sleep(for: .seconds(delay))
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
        guard !isRefreshing else {
            let waitSuffix = isWaitingForNetwork ? " (waiting for a network path)" : ""
            DebugLog.shared.record("Refresh ignored — a poll is already running\(waitSuffix)", category: .poll)
            return
        }
        isRefreshing = true
        pollSequence += 1
        let token = pollSequence
        inFlightPoll = token
        defer {
            isRefreshing = false
            inFlightPoll = nil
            // The wait, if there was one, ended when the request did — whichever
            // way it ended.
            isWaitingForNetwork = false
        }
        lastChecked = Date()
        let client = clientProvider()
        do {
            let response = try await client.fetchStatus(
                onWaitingForConnectivity: { [weak self] in
                    // Delivered on URLSession's delegate queue, so the hop to
                    // this actor is this side's job. It is also what makes the
                    // token necessary: the hop can outlive the request.
                    Task { @MainActor in self?.noteWaitingForNetwork(token: token) }
                })
            lastResponse = response
            lastSucceeded = Date()
            consecutiveFailures = 0
            let newState = LittleSister.displayState(for: response.status)
            DebugLog.shared.record("Poll: \(newState.label)", category: .poll)
            await applyState(newState)
        } catch let error as APIError {
            consecutiveFailures += 1
            lastFailureClass = error.retryClass
            let reason = Self.pollFailureReason(from: error, waitingForNetwork: isWaitingForNetwork, pollInterval: currentPollInterval)
            DebugLog.shared.record("Poll failed: \(reason)", category: .poll)
            await applyState(.unavailable(reason: reason))
        } catch is CancellationError {
            // Not a failure: the loop was torn down mid-request. Recorded, but it
            // must not touch the failure count or the displayed state.
            DebugLog.shared.record("Poll cancelled", category: .poll)
        } catch {
            // `fetchStatus` only throws `APIError`, so this should be unreachable —
            // but "unreachable in practice" is exactly what was said about the
            // notification post that reached nobody (ADR-0008). Failing silently
            // here would advance `lastChecked` without a log line, a state change,
            // or a failure count, so the menu would keep ticking while the app did
            // nothing. Treat an unknown error as the failure it is.
            consecutiveFailures += 1
            // Transient by default: an unrecognized error is precisely the case
            // where nothing justifies deciding it will never heal.
            lastFailureClass = .transient
            let reason = "Unexpected error: \(error.localizedDescription)"
            DebugLog.shared.record("Poll failed: \(reason)", category: .poll)
            await applyState(.unavailable(reason: reason))
        }
    }

    // MARK: - Waiting for network

    // A connectivity wait is reported, never *decided on*: this sets a flag the
    // menu reads and writes one log line, and it must stay out of
    // `applyState(_:)`. Routing it into `.unavailable(reason:)` would make every
    // wait a state change, and the notification machinery fires on case changes
    // — so a healthy → waiting → healthy blip would emit "Monitoring status
    // unavailable" and then "available again" for a hiccup that resolved itself
    // in two seconds (ADR-0011 §3).
    //
    // Internal so tests can stand in for the delegate, which no test can provoke
    // — the callback fires only when there is no viable network path.
    func noteWaitingForNetwork(token: Int) {
        // Only the poll that is actually running may raise the flag: the hop
        // from the delegate queue can land after its own request finished, and
        // nothing would lower a flag raised then.
        guard token == inFlightPoll else { return }
        // One line per poll rather than per callback — URLSession may report the
        // wait more than once for a single task.
        guard !isWaitingForNetwork else { return }
        isWaitingForNetwork = true
        DebugLog.shared.record("Waiting for network…", category: .poll)
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

    // MARK: - Retry schedule

    // How long to wait before the next poll.
    //
    // A cold boot can leave the network path unready for the first attempt or
    // two, and waiting a full interval after each timeout left the app
    // "unavailable" for around 90 seconds after every restart. So while polls
    // are failing the delay starts at 5s and doubles with each consecutive
    // failure, capped at the configured interval: a transient outage recovers
    // quickly, while a server that is genuinely down settles back to the normal
    // cadence rather than being polled twelve times as often all night
    // (ADR-0010).
    //
    // That schedule is for failures that might heal unaided. A definite answer —
    // a rejected token, a node path that does not exist, an ATS refusal — is not
    // one: asking again cannot change it, and repetition is what costs something
    // at the other end, so it waits the configured interval floored at a minute,
    // whatever the failure count (ADR-0011 §4). Putting it on the fast end of a
    // backoff meant for outages would be exactly backwards.
    //
    // A floor, not a long fixed penalty, because recovery must not depend on
    // waiting it out — and does not: committing Settings calls manualRefresh(),
    // so a corrected token is retried the instant the user presses OK
    // (ADR-0004). This governs only how often the app asks unprompted.
    //
    // Pure and static so the schedule can be tested without running a loop.
    static let firstRetryDelay = 5
    static let definiteRetryFloor = 60

    static func retryDelay(
        consecutiveFailures: Int, pollInterval: Int, retryClass: RetryClass
    ) -> Int {
        guard consecutiveFailures > 0 else { return pollInterval }
        switch retryClass {
        case .definite:
            // Deliberately independent of the count: there is nothing to back
            // off from when every attempt gets the same answer.
            return max(pollInterval, definiteRetryFloor)
        case .transient:
            // Bound the shift far below Int's width; min() below caps the result
            // anyway, but an unbounded shift would be undefined for a long enough
            // outage.
            let doublings = min(consecutiveFailures - 1, 16)
            return min(firstRetryDelay << doublings, pollInterval)
        }
    }

    // The loop enforces the setting's floor on whatever the provider hands
    // back — a provider is not obliged to have gone through Settings. The bound
    // itself belongs to the setting, so it is read from `AppSettings` rather
    // than given a second name here.
    //
    // Internal, not private, so the clamp and the live re-read are testable
    // without running the loop.
    var currentPollInterval: Int {
        max(AppSettings.minimumPollInterval, intervalProvider())
    }

    // The one place an APIError becomes words a user reads. Static and internal
    // so the wording is testable without standing up a view model; it needs
    // nothing from self.
    static func errorReason(from error: APIError) -> String {
        switch error {
        case .noConnection:
            return "No network connection"
        case .cannotResolveHost(let host):
            guard let host else { return "Cannot resolve the server name" }
            return "Cannot resolve \(host)"
        case .cannotConnect(let host):
            guard let host else { return "Cannot connect to the server" }
            return "Cannot connect to \(host)"
        case .connectionLost:
            return "Connection lost"
        case .timeout:
            return "Request timed out"
        case .blockedByAppTransportSecurity:
            // The one reason that has to name the fix, because nothing about the
            // symptom suggests this Mac is the thing refusing: the same URL opens
            // fine in the user's browser.
            return "Plain HTTP is blocked by macOS; use https://"
        case .networkError(let code):
            return "Network error (\(code))"
        case .unauthorized(let detail):
            return detail ?? "Unauthorized"
        case .notFound(let detail):
            return detail ?? "Node path not found"
        case .serverError(let code, let detail):
            return detail ?? "Server error (\(code))"
        case .invalidResponse:
            return "Invalid response"
        case .unsupportedSchemaVersion(let v):
            return "Server speaks schema_version \(v); this app supports 1 — update the app"
        case .contractMismatch(let detail):
            return "Server response no longer matches the API this app knows "
                + "— both speak schema_version 1, so the contract likely changed "
                + "within the version; update the app. First mismatch: \(detail)"
        }
    }

    // Pure. Returns the reason to show for a failed poll. When a parked request
    // times out before the network path became viable, the generic "Request timed
    // out" implies the server was slow — but the request never left this Mac, so
    // the actual cause is reported instead. All other failures use errorReason(from:).
    static func pollFailureReason(from error: APIError, waitingForNetwork: Bool, pollInterval: Int) -> String {
        if waitingForNetwork, case .timeout = error {
            return timeoutWhileWaitingReason(pollInterval: pollInterval)
        }
        return errorReason(from: error)
    }

    static func timeoutWhileWaitingReason(pollInterval: Int) -> String {
        let budget = StatusAPIClient.timeoutBudget(pollInterval: pollInterval)
        return "No usable network path (waited \(budget) s) — the request never left this Mac"
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

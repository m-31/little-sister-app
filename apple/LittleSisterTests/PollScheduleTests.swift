//
//  PollScheduleTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

@Suite("Poll retry schedule")
@MainActor
struct PollScheduleTests {

    // The backoff below is the *transient* schedule (ADR-0010); the class is
    // spelled out at every call rather than defaulted, because "which schedule"
    // is part of asking the question (ADR-0011 §4).
    private func transientDelay(_ failures: Int, interval: Int) -> Int {
        MonitoringViewModel.retryDelay(
            consecutiveFailures: failures, pollInterval: interval, retryClass: .transient)
    }

    private func definiteDelay(_ failures: Int, interval: Int) -> Int {
        MonitoringViewModel.retryDelay(
            consecutiveFailures: failures, pollInterval: interval, retryClass: .definite)
    }

    @Test("With no failures, polling runs at the configured interval")
    func healthyCadence() {
        #expect(transientDelay(0, interval: 60) == 60)
        // A success is a success whatever failed last: with no failures to
        // schedule around, the class must not be able to slow the loop down.
        #expect(definiteDelay(0, interval: 60) == 60)
        #expect(definiteDelay(0, interval: 5) == 5)
    }

    @Test("The delay starts at 5s and doubles with each consecutive failure")
    func backoffDoubles() {
        let delays = (1...4).map { transientDelay($0, interval: 60) }
        #expect(delays == [5, 10, 20, 40])
    }

    @Test("The delay never exceeds the configured interval")
    func backoffCapsAtInterval() {
        #expect(transientDelay(5, interval: 60) == 60)
        #expect(transientDelay(99, interval: 60) == 60)
        // A long outage must not overflow the shift.
        #expect(transientDelay(10_000, interval: 60) == 60)
    }

    @Test("A short configured interval is never lengthened by the retry floor")
    func shortIntervalIsNotStretched() {
        #expect(transientDelay(1, interval: 5) == 5)
        #expect(transientDelay(3, interval: 5) == 5)
    }

    @Test("The schedule never returns a delay below the retry floor")
    func neverFasterThanTheFloor() {
        for failures in 1...20 {
            #expect(transientDelay(failures, interval: 60) >= MonitoringViewModel.firstRetryDelay)
        }
    }

    // MARK: - A definite answer waits

    // ADR-0011 §4: a 401, a 404, an unsupported schema version or an ATS refusal
    // will not heal by being asked again, and asking is what costs something at
    // the other end. The floor is what stops the hammering — at the default
    // interval it changes nothing at all.
    @Test("A definite failure waits the interval, floored at a minute")
    func definiteWaitsAtLeastAMinute() {
        #expect(definiteDelay(1, interval: 5) == 60)     // 12× fewer attempts
        #expect(definiteDelay(1, interval: 60) == 60)    // the default: unchanged
        #expect(definiteDelay(1, interval: 300) == 300)  // a long interval is obeyed, not shortened
    }

    @Test("A definite failure does not back off — the count cannot change the answer")
    func definiteIgnoresTheFailureCount() {
        let delays = [1, 2, 3, 10, 10_000].map { definiteDelay($0, interval: 5) }
        #expect(delays.allSatisfy { $0 == 60 })
    }

    // Swept over raw intervals rather than plausible ones: `retryDelay` does no
    // clamping of its own (the loop's `currentPollInterval` does that), so the
    // property has to hold for whatever it is handed.
    @Test("A definite failure is never retried sooner than a transient one")
    func definiteIsNeverFasterThanTransient() {
        for interval in [1, 5, 7, 60, 300] {
            for failures in 1...20 {
                #expect(definiteDelay(failures, interval: interval)
                        >= transientDelay(failures, interval: interval))
            }
        }
    }

    // MARK: - Which failures are definite

    // The compiler is the real guard here: `retryClass` switches without a
    // `default`, so a case added later cannot compile until it picks a side.
    // This pins the choices that switch actually makes, since a wrong-but-
    // exhaustive table would compile just as happily.
    @Test("Every APIError case lands on the side ADR-0011 §4 puts it")
    func classificationMatchesTheAdrTable() {
        let transient: [APIError] = [
            .noConnection,
            .cannotResolveHost(host: "nas1"),
            .cannotConnect(host: "nas1"),
            .connectionLost,
            .timeout,
            .networkError(code: -1200),
            .serverError(statusCode: 503, detail: nil),
            .invalidResponse,
        ]
        let definite: [APIError] = [
            .unauthorized(detail: nil),
            .notFound(detail: nil),
            .unsupportedSchemaVersion(2),
            .blockedByAppTransportSecurity,
        ]
        for error in transient {
            #expect(error.retryClass == .transient, "\(error) should be transient")
        }
        for error in definite {
            #expect(error.retryClass == .definite, "\(error) should be definite")
        }
    }

    // Called out separately because it is the one definite case that is *not* an
    // answer from the server: ATS refuses the request before it leaves this Mac,
    // and no retry schedule will ever make it relent — only a base URL the user
    // changes in Settings, which triggers its own immediate refresh.
    @Test("An ATS refusal is definite, not a network failure to back off from")
    func atsRefusalIsDefinite() {
        #expect(APIError.blockedByAppTransportSecurity.retryClass == .definite)
        #expect(definiteDelay(1, interval: 5) > transientDelay(1, interval: 5))
    }

    // MARK: - The configured interval

    // A mutable stand-in for AppSettings, so a change can be observed without
    // touching UserDefaults.
    @MainActor
    private final class IntervalBox {
        var seconds: Int
        init(_ seconds: Int) { self.seconds = seconds }
    }

    private func makeViewModel(_ box: IntervalBox) -> MonitoringViewModel {
        MonitoringViewModel(
            clientProvider: {
                StatusAPIClient(
                    baseURL: URL(string: "http://nas1:8000")!,
                    nodePath: nil,
                    token: "tok"
                )
            },
            notificationSender: NotificationSpy(),
            intervalProvider: { box.seconds }
        )
    }

    // ADR-0011 §2 derives the session's timeouts from the interval on every
    // poll, so the loop must not be running on a copy captured at launch: the
    // two would disagree after a settings change, which is worse than both
    // being stale.
    @Test("The configured interval is re-read, not captured at init")
    func intervalIsLive() {
        let box = IntervalBox(60)
        let vm = makeViewModel(box)
        #expect(vm.currentPollInterval == 60)
        box.seconds = 15
        #expect(vm.currentPollInterval == 15)
    }

    @Test("A provider below the setting's minimum is clamped rather than obeyed")
    func intervalIsClamped() {
        let box = IntervalBox(1)
        let vm = makeViewModel(box)
        #expect(vm.currentPollInterval == AppSettings.minimumPollInterval)
        box.seconds = 0
        #expect(vm.currentPollInterval == AppSettings.minimumPollInterval)
    }

    @Test("The default provider is the default interval, with no settings read")
    func defaultProviderIsTheDefaultInterval() {
        let vm = MonitoringViewModel(
            clientProvider: {
                StatusAPIClient(
                    baseURL: URL(string: "http://nas1:8000")!,
                    nodePath: nil,
                    token: "tok"
                )
            },
            notificationSender: NotificationSpy()
        )
        #expect(vm.currentPollInterval == AppSettings.defaultPollInterval)
    }
}

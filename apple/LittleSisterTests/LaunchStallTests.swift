//
//  LaunchStallTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

// Tests for the never-left-this-Mac wording when a parked poll exhausts its
// budget. The composition is pure — no network, no live view model needed.
// (The connectivity wait itself remains untestable in-process — the existing
// comment on ConnectivityWaitObserver explains why; the live launch check
// in the slice-3 verification covers it end-to-end.)
@Suite("Launch stall wording")
@MainActor
struct LaunchStallTests {

    // timeoutBudget(60) = min(30, 60 * 4/5) = 30
    @Test(".timeout with the wait flag produces the never-left-this-Mac wording")
    func timeoutWhileWaitingYieldsNetworkPathReason() {
        let reason = MonitoringViewModel.pollFailureReason(
            from: .timeout, waitingForNetwork: true, pollInterval: 60)
        #expect(reason.contains("never left this Mac"))
        #expect(reason.contains("30"))
    }

    @Test(".timeout without the wait flag keeps the existing 'Request timed out' wording")
    func timeoutWithoutFlagKeepsExistingReason() {
        let reason = MonitoringViewModel.pollFailureReason(
            from: .timeout, waitingForNetwork: false, pollInterval: 60)
        #expect(reason == "Request timed out")
    }

    @Test("a non-timeout network error with the wait flag is not overridden")
    func nonTimeoutErrorWithFlagIsNotOverridden() {
        // The override is exclusive to .timeout — other network-layer reasons
        // already point at this Mac or the path, and the flag being up does not
        // change what those failures mean.
        let reason = MonitoringViewModel.pollFailureReason(
            from: .noConnection, waitingForNetwork: true, pollInterval: 60)
        #expect(reason == "No network connection")
    }

    @Test("the wording includes the budget's seconds for the given interval")
    func timeoutReasonIncludesBudgetSeconds() {
        // pollInterval 5  → budget = min(30, 5 * 4/5) = 4
        let shortReason = MonitoringViewModel.pollFailureReason(
            from: .timeout, waitingForNetwork: true, pollInterval: 5)
        #expect(shortReason.contains("4"))
        // pollInterval 60 → budget = min(30, 60 * 4/5) = 30
        let longReason = MonitoringViewModel.pollFailureReason(
            from: .timeout, waitingForNetwork: true, pollInterval: 60)
        #expect(longReason.contains("30"))
    }
}

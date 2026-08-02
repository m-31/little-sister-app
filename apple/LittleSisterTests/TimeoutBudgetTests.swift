//
//  TimeoutBudgetTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

// ADR-0011 §2: both session timeouts come from one budget derived from the poll
// interval, so a user who asks for a fast cadence gets one instead of having it
// overruled by a constant that knows nothing about it. The derivation is pure,
// so the whole table is pinned here without a network.
@Suite("Timeout budget")
@MainActor
struct TimeoutBudgetTests {

    private func budget(_ interval: Int) -> Int {
        StatusAPIClient.timeoutBudget(pollInterval: interval)
    }

    private func idle(_ interval: Int) -> Int {
        StatusAPIClient.requestTimeout(pollInterval: interval)
    }

    @Test("The default 60s interval keeps the 30s budget it had as a constant")
    func defaultIntervalIsUnchanged() {
        #expect(budget(AppSettings.defaultPollInterval) == 30)
        #expect(idle(AppSettings.defaultPollInterval) == 15)
    }

    @Test("Between the floor and the cap the budget is 80% of the interval")
    func eightyPercentInTheBand() {
        #expect(budget(10) == 8)
        #expect(budget(20) == 16)
        #expect(budget(30) == 24)
    }

    @Test("A long interval does not license a long hang")
    func cappedAtThirtySeconds() {
        #expect(budget(300) == 30)
        #expect(budget(3600) == 30)
    }

    // The 4 is not a constant of its own: it is 80% of the smallest interval
    // the setting allows, which is why nothing has to keep it below the floor
    // the polling loop clamps to. Anything at or under that minimum lands on
    // the same budget, including values no caller should produce — a zero or
    // negative timeout would mean "no limit" to URLSession.
    @Test("Any interval at or below the setting's minimum yields the same budget")
    func flooredAtTheSettingsMinimum() {
        let atMinimum = budget(AppSettings.minimumPollInterval)
        #expect(atMinimum == 4)
        #expect(budget(1) == atMinimum)
        #expect(budget(0) == atMinimum)
        #expect(budget(-10) == atMinimum)
    }

    @Test("The idle timeout is half the budget")
    func idleIsHalfTheBudget() {
        #expect(idle(5) == 2)
        #expect(idle(20) == 8)
        #expect(idle(3600) == 15)
    }

    // The point of the whole derivation: the sequential loop sleeps after a poll
    // returns, so a budget that fills the interval leaves no room for the sleep
    // and the configured cadence can never be met while the server is
    // unreachable. Strictly less, therefore — and swept from raw inputs, not
    // from the minimum, because the app derives the budget from an unclamped
    // `AppSettings` value while only the loop clamps.
    @Test("A poll always finishes inside the interval it was scheduled at")
    func budgetAlwaysFitsInsideTheInterval() {
        for raw in -10...600 {
            #expect(budget(raw) < max(AppSettings.minimumPollInterval, raw))
        }
        #expect(budget(AppSettings.maximumPollInterval) < AppSettings.maximumPollInterval)
    }

    // MARK: - Applying the budget

    // Everything above pins the derivation; this is the seam where it becomes
    // behavior. Transpose the two assignments in makeSession — the outer cap
    // taking the idle value and vice versa — and every test above still passes
    // while the app runs a 15-second cap under a 30-second idle timeout.
    @Test("makeSession puts each derived value on the setting it belongs to")
    func sessionCarriesTheDerivedTimeouts() {
        let config = StatusAPIClient.makeSession(
            pollInterval: AppSettings.defaultPollInterval).configuration
        #expect(config.timeoutIntervalForResource == 30)
        #expect(config.timeoutIntervalForRequest == 15)
        #expect(config.waitsForConnectivity)
    }

    @Test("A fast interval reaches the session as the floored pair")
    func sessionAtTheFloor() {
        let config = StatusAPIClient.makeSession(pollInterval: 5).configuration
        #expect(config.timeoutIntervalForResource == 4)
        #expect(config.timeoutIntervalForRequest == 2)
        #expect(config.waitsForConnectivity)
    }

    // Idle tighter than the outer cap is the layering ADR-0011 §2 settled on:
    // with waitsForConnectivity the outer cap covers a period during which the
    // idle timer is not running at all.
    @Test("The idle timeout is never looser than the whole-attempt cap")
    func idleIsTighterThanTheOuterCap() {
        for interval in [AppSettings.minimumPollInterval, 7, 10, 37, 60, 120,
                         AppSettings.maximumPollInterval] {
            #expect(idle(interval) <= budget(interval))
            // Never zero, whatever the arithmetic does — URLSession reads a
            // zero timeout as no limit at all.
            #expect(idle(interval) > 0)
        }
    }
}

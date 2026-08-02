//
//  V12ContractTests.swift
//  LittleSisterTests
//
//  Tests for the v1.2 contract changes: nullable timestamp, observedLine rules,
//  stale-aware warn mapping, and no-notification-churn guarantee.
//

import Testing
import Foundation
@testable import LittleSister

private func makeDecoder() -> JSONDecoder { StatusAPIClient.makeDecoder() }

@Suite("v1.2 Contract")
struct V12ContractTests {

    // MARK: - Decoding: nullable timestamp

    @Test("Root with null timestamp above a stamped child decodes successfully")
    func rootNullTimestampWithStampedChild() throws {
        let json = """
        {
            "schema_version": 1,
            "generated_at": "2026-07-30T10:00:00Z",
            "status": {
                "path": "/",
                "name": "root",
                "own_code": "OK",
                "code": "OK",
                "reasons": [],
                "timestamp": null,
                "maintenance": false,
                "stale": false,
                "children": [{
                    "path": "/alpha",
                    "name": "alpha",
                    "own_code": "OK",
                    "code": "OK",
                    "reasons": [],
                    "timestamp": "2026-07-30T09:59:55Z",
                    "maintenance": false,
                    "stale": false,
                    "children": []
                }]
            }
        }
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(StatusResponse.self, from: json)
        #expect(response.status.timestamp == nil)
        let child = try #require(response.status.children.first)
        #expect(child.timestamp != nil)
    }

    @Test("Root with null timestamp maps to healthy state")
    func rootNullTimestampMapsToHealthy() throws {
        let json = """
        {
            "schema_version": 1,
            "generated_at": "2026-07-30T10:00:00Z",
            "status": {
                "path": "/",
                "name": "root",
                "own_code": "OK",
                "code": "OK",
                "reasons": [],
                "timestamp": null,
                "maintenance": false,
                "stale": false,
                "children": []
            }
        }
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(StatusResponse.self, from: json)
        #expect(displayState(for: response.status) == .healthy)
    }

    @Test("Present timestamp still decodes to non-nil Date")
    func presentTimestampDecodes() throws {
        let json = """
        {
            "schema_version": 1,
            "generated_at": "2026-07-30T10:00:00Z",
            "status": {
                "path": "/node2",
                "name": "node2",
                "own_code": "OK",
                "code": "OK",
                "reasons": [],
                "timestamp": "2026-07-30T09:59:55Z",
                "maintenance": false,
                "stale": false,
                "children": []
            }
        }
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(StatusResponse.self, from: json)
        #expect(response.status.timestamp != nil)
    }

    // MARK: - observedLine three rules

    @Test("Stamp present → line starts with Observed:")
    func stampPresentRendersLine() {
        // Use a date clearly in the past — not today — to exercise the date-prefix branch.
        let past = Date(timeIntervalSince1970: 1_000_000_000) // 2001-09-08
        let line = observedLine(timestamp: past, stale: false)
        #expect(line?.hasPrefix("Observed: ") == true)
        #expect(line?.contains("(stale)") == false)
    }

    @Test("Stamp present + stale → suffix appended")
    func stampPresentWithStaleHasSuffix() {
        let past = Date(timeIntervalSince1970: 1_000_000_000)
        let line = observedLine(timestamp: past, stale: true)
        #expect(line?.hasPrefix("Observed: ") == true)
        #expect(line?.contains("(stale)") == true)
    }

    @Test("Null stamp + stale → Observed: —  (stale)")
    func nullStampWithStaleShowsDash() {
        #expect(observedLine(timestamp: nil, stale: true) == "Observed: —  (stale)")
    }

    @Test("Null stamp + not stale → nil (no line)")
    func nullStampNotStaleProducesNoLine() {
        #expect(observedLine(timestamp: nil, stale: false) == nil)
    }

    // MARK: - displayState: warn carries stale

    @Test("WARN + stale=true → warning(isStale: true)")
    func warnStaleIsStaleWarning() {
        let node = StatusNode(
            path: "/",
            name: "root",
            ownCode: .warn,
            code: .warn,
            reasons: ["slow"],
            timestamp: nil,
            frequencySeconds: nil,
            maintenance: false,
            stale: true,
            children: []
        )
        #expect(displayState(for: node) == .warning(isStale: true))
    }

    @Test("WARN + stale=false → warning(isStale: false)")
    func warnNotStaleIsNotStaleWarning() {
        let node = StatusNode(
            path: "/",
            name: "root",
            ownCode: .warn,
            code: .warn,
            reasons: ["slow"],
            timestamp: nil,
            frequencySeconds: nil,
            maintenance: false,
            stale: false,
            children: []
        )
        #expect(displayState(for: node) == .warning(isStale: false))
    }

    // MARK: - No notification churn when only the stale flag flips

    @Test("warning(isStale: false) → warning(isStale: true) fires no notification")
    func warnStaleFlipDoesNotNotify() {
        #expect(notification(from: .warning(isStale: false), to: .warning(isStale: true)) == nil)
    }

    @Test("warning(isStale: true) → warning(isStale: false) fires no notification")
    func warnStaleUnflipDoesNotNotify() {
        #expect(notification(from: .warning(isStale: true), to: .warning(isStale: false)) == nil)
    }
}

//
//  DisplayStateTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

private func makeNode(
    code: StatusCode,
    stale: Bool = false,
    reasons: [String] = []
) -> StatusNode {
    StatusNode(
        path: "/",
        name: "root",
        ownCode: code,
        code: code,
        reasons: reasons,
        timestamp: Date(),
        frequencySeconds: nil,
        maintenance: code == .maintenance,
        stale: stale,
        children: []
    )
}

@Suite("Mapping")
struct MappingTests {

    @Test("OK + stale=false → healthy")
    func okNotStaleIsHealthy() {
        #expect(displayState(for: makeNode(code: .ok, stale: false)) == .healthy)
    }

    @Test("OK + stale=true → warning(isStale: true)")
    func okStaleIsWarning() {
        #expect(displayState(for: makeNode(code: .ok, stale: true)) == .warning(isStale: true))
    }

    @Test("WARN → warning(isStale: false)")
    func warnIsWarning() {
        #expect(displayState(for: makeNode(code: .warn)) == .warning(isStale: false))
    }

    @Test("ERROR → error")
    func errorIsError() {
        #expect(displayState(for: makeNode(code: .error)) == .error)
    }

    @Test("MAINTENANCE → maintenance")
    func maintenanceIsMaintenance() {
        #expect(displayState(for: makeNode(code: .maintenance)) == .maintenance)
    }

    @Test("UNDEFINED → undefined, uses first reason when present")
    func undefinedIsUndefined() {
        #expect(
            displayState(for: makeNode(code: .undefined, reasons: ["no data"]))
            == .undefined(reason: "no data")
        )
    }

    @Test("UNDEFINED with no reasons → undefined with fallback string")
    func undefinedNoReasonsUsesFallback() {
        if case .undefined = displayState(for: makeNode(code: .undefined, reasons: [])) {
            // any non-empty reason string is acceptable
        } else {
            #expect(Bool(false), "Expected .undefined")
        }
    }
}

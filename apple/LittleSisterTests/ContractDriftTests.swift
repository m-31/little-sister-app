//
//  ContractDriftTests.swift
//  LittleSisterTests
//
//  Tests for the contract-drift probe introduced in StatusAPIClient.decodeResponse
//  (ADR-0011 §4 extension). Neutral fixtures only — example.org, alpha, node2.
//

import Testing
import Foundation
@testable import LittleSister

@Suite("Contract drift taxonomy")
@MainActor
struct ContractDriftTests {

    // MARK: - Same-version drift → contractMismatch

    @Test("code as a number produces contractMismatch with definite retry class")
    func sameVersionDriftIsContractMismatch() {
        // own_code / code are strings in the contract; sending numbers is a
        // type mismatch — the canonical same-version drift fixture.
        let json = """
        {
            "schema_version": 1,
            "generated_at": "2026-07-30T10:00:00Z",
            "status": {
                "path": "/",
                "name": "alpha",
                "own_code": 42,
                "code": 42,
                "reasons": [],
                "timestamp": null,
                "maintenance": false,
                "stale": false,
                "children": []
            }
        }
        """.data(using: .utf8)!

        do {
            _ = try StatusAPIClient.decodeResponse(json)
            #expect(Bool(false), "Expected contractMismatch to be thrown")
        } catch let error as APIError {
            guard case .contractMismatch(let detail) = error else {
                #expect(Bool(false), "Expected .contractMismatch, got \(error)")
                return
            }
            #expect(error.retryClass == .definite)
            // detail names the coding path, e.g. "status.own_code — type mismatch"
            #expect(detail.contains("."))
            #expect(!detail.isEmpty)
        } catch {
            #expect(Bool(false), "Unexpected non-APIError: \(error)")
        }
    }

    @Test("contractMismatch reason names the coding path and both schema versions")
    func contractMismatchReasonContainsPath() {
        let json = """
        {
            "schema_version": 1,
            "generated_at": "2026-07-30T10:00:00Z",
            "status": {
                "path": "/node2",
                "name": "node2",
                "own_code": 42,
                "code": 42,
                "reasons": [],
                "timestamp": null,
                "maintenance": false,
                "stale": false,
                "children": []
            }
        }
        """.data(using: .utf8)!

        do {
            _ = try StatusAPIClient.decodeResponse(json)
            #expect(Bool(false), "Expected contractMismatch to be thrown")
        } catch let error as APIError {
            guard case .contractMismatch(let detail) = error else {
                #expect(Bool(false), "Expected .contractMismatch, got \(error)")
                return
            }
            let reason = MonitoringViewModel.errorReason(from: error)
            // Reason mentions both schema versions and ends with the detail.
            #expect(reason.contains("schema_version 1"))
            #expect(reason.hasSuffix(detail))
        } catch {
            #expect(Bool(false), "Unexpected non-APIError: \(error)")
        }
    }

    // MARK: - Garbage bytes → invalidResponse (transient)

    @Test("Garbage bytes produce invalidResponse with transient retry class")
    func garbageBytesIsInvalidResponse() {
        let garbage = Data([0xFF, 0xFE, 0x00, 0x01, 0x02])

        do {
            _ = try StatusAPIClient.decodeResponse(garbage)
            #expect(Bool(false), "Expected invalidResponse to be thrown")
        } catch let error as APIError {
            guard case .invalidResponse = error else {
                #expect(Bool(false), "Expected .invalidResponse, got \(error)")
                return
            }
            #expect(error.retryClass == .transient)
        } catch {
            #expect(Bool(false), "Unexpected non-APIError: \(error)")
        }
    }

    // MARK: - schema_version 2 → unsupportedSchemaVersion (both-numbers wording)

    @Test("schema_version 2 envelope produces unsupportedSchemaVersion with both-numbers wording")
    func versionTwoIsUnsupportedWithBothNumbers() {
        let json = """
        {
            "schema_version": 2,
            "generated_at": "2026-07-30T10:00:00Z",
            "status": {
                "path": "/",
                "name": "alpha",
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

        do {
            _ = try StatusAPIClient.decodeResponse(json)
            #expect(Bool(false), "Expected unsupportedSchemaVersion to be thrown")
        } catch let error as APIError {
            guard case .unsupportedSchemaVersion(let v) = error else {
                #expect(Bool(false), "Expected .unsupportedSchemaVersion, got \(error)")
                return
            }
            #expect(v == 2)
            let reason = MonitoringViewModel.errorReason(from: error)
            // "Server speaks schema_version 2; this app supports 1 — update the app"
            #expect(reason.contains("schema_version 2"))
            #expect(reason.contains("supports 1"))
        } catch {
            #expect(Bool(false), "Unexpected non-APIError: \(error)")
        }
    }
}

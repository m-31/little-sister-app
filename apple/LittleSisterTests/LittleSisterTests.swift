//
//  LittleSisterTests.swift
//  LittleSisterTests
//
//  Created by Michael Meyling on 2026-07-01.
//

import Testing
import Foundation
@testable import LittleSister

private func makeDecoder() -> JSONDecoder {
    StatusAPIClient.makeDecoder()
}

@Suite("API Decoding")
struct APIDecodingTests {

    // Minimal valid node — reused by several tests that don't care about node content.
    private let rootNodeJSON = """
        {
            "path": "/",
            "name": "root",
            "own_code": "OK",
            "code": "OK",
            "reasons": [],
            "timestamp": "2026-06-25T18:04:55Z",
            "maintenance": false,
            "stale": false,
            "children": []
        }
        """

    private func envelope(
        schemaVersion: Int = 1,
        generatedAt: String = "2026-06-25T18:05:00Z",
        status: String
    ) -> Data {
        """
        {"schema_version":\(schemaVersion),"generated_at":"\(generatedAt)","status":\(status)}
        """.data(using: .utf8)!
    }

    // MARK: - Tests

    @Test("Valid StatusResponse with schema_version 1")
    func validStatusResponse() throws {
        let response = try makeDecoder().decode(
            StatusResponse.self,
            from: envelope(status: rootNodeJSON)
        )
        #expect(response.schemaVersion == 1)
        #expect(response.status.path == "/")
        #expect(response.status.name == "root")
        #expect(response.status.code == .ok)
        #expect(response.status.reasons.isEmpty)
        #expect(response.status.maintenance == false)
        #expect(response.status.stale == false)
    }

    @Test("Nested children are decoded recursively")
    func nestedChildren() throws {
        let json = """
        {
            "schema_version": 1,
            "generated_at": "2026-06-25T18:05:00Z",
            "status": {
                "path": "/",
                "name": "root",
                "own_code": "OK",
                "code": "OK",
                "reasons": [],
                "timestamp": "2026-06-25T18:04:55Z",
                "maintenance": false,
                "stale": false,
                "children": [{
                    "path": "/system",
                    "name": "system",
                    "own_code": "WARN",
                    "code": "WARN",
                    "reasons": ["disk near capacity"],
                    "timestamp": "2026-06-25T18:04:50Z",
                    "maintenance": false,
                    "stale": false,
                    "children": [{
                        "path": "/system/db",
                        "name": "db",
                        "own_code": "WARN",
                        "code": "WARN",
                        "reasons": ["disk near capacity"],
                        "timestamp": "2026-06-25T18:04:45Z",
                        "maintenance": false,
                        "stale": false,
                        "children": []
                    }]
                }]
            }
        }
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(StatusResponse.self, from: json)
        #expect(response.status.children.count == 1)
        let system = response.status.children[0]
        #expect(system.name == "system")
        #expect(system.code == .warn)
        #expect(system.children.count == 1)
        #expect(system.children[0].name == "db")
        #expect(system.children[0].children.isEmpty)
    }

    @Test("frequency_seconds null decodes as nil")
    func frequencySecondsNull() throws {
        let nodeJSON = """
        {
            "path": "/",
            "name": "root",
            "own_code": "OK",
            "code": "OK",
            "reasons": [],
            "timestamp": "2026-06-25T18:04:55Z",
            "frequency_seconds": null,
            "maintenance": false,
            "stale": false,
            "children": []
        }
        """
        let response = try makeDecoder().decode(
            StatusResponse.self,
            from: envelope(status: nodeJSON)
        )
        #expect(response.status.frequencySeconds == nil)
    }

    @Test("All five StatusCode values decode correctly",
          arguments: ["OK", "WARN", "ERROR", "MAINTENANCE", "UNDEFINED"])
    func allStatusCodeValues(rawValue: String) throws {
        let data = "\"\(rawValue)\"".data(using: .utf8)!
        let code = try JSONDecoder().decode(StatusCode.self, from: data)
        #expect(code.rawValue == rawValue)
    }

    @Test("Timestamp without fractional seconds is decoded")
    func timestampWithoutFractionalSeconds() throws {
        // "2026-06-25T18:04:55Z" — no fractional part
        let response = try makeDecoder().decode(
            StatusResponse.self,
            from: envelope(generatedAt: "2026-06-25T18:05:00Z", status: rootNodeJSON)
        )
        #expect(response.generatedAt > Date.distantPast)
        #expect(response.status.timestamp > Date.distantPast)
    }

    @Test("Timestamp with fractional seconds is decoded")
    func timestampWithFractionalSeconds() throws {
        // "2026-06-26T14:46:40.593277Z" — has fractional part; rejected by plain .iso8601
        let nodeJSON = """
        {
            "path": "/",
            "name": "root",
            "own_code": "OK",
            "code": "OK",
            "reasons": [],
            "timestamp": "2026-06-26T14:46:35.123456Z",
            "maintenance": false,
            "stale": false,
            "children": []
        }
        """
        let response = try makeDecoder().decode(
            StatusResponse.self,
            from: envelope(generatedAt: "2026-06-26T14:46:40.593277Z", status: nodeJSON)
        )
        #expect(response.generatedAt > Date.distantPast)
        #expect(response.status.timestamp > Date.distantPast)
    }

    @Test("Unknown fields in envelope and node are ignored")
    func unknownFieldsIgnored() throws {
        let json = """
        {
            "schema_version": 1,
            "generated_at": "2026-06-25T18:05:00Z",
            "unexpected_envelope_field": true,
            "status": {
                "path": "/",
                "name": "root",
                "own_code": "OK",
                "code": "OK",
                "reasons": [],
                "timestamp": "2026-06-25T18:04:55Z",
                "maintenance": false,
                "stale": false,
                "children": [],
                "about": "the root node",
                "title": "Root",
                "description": "checks everything",
                "config": "yaml: here",
                "maintenance_details": null
            }
        }
        """.data(using: .utf8)!
        let response = try makeDecoder().decode(StatusResponse.self, from: json)
        #expect(response.schemaVersion == 1)
        #expect(response.status.name == "root")
    }

    @Test("Unsupported schema major is rejected during decoding")
    func unsupportedSchemaMajorRejected() {
        #expect(throws: UnsupportedSchemaVersionError.self) {
            _ = try makeDecoder().decode(
                StatusResponse.self,
                from: envelope(schemaVersion: 2, status: rootNodeJSON)
            )
        }
    }
}

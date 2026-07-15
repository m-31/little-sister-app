//
//  Models.swift
//  LittleSister
//

import Foundation

enum StatusCode: String, Decodable {
    case ok = "OK"
    case warn = "WARN"
    case error = "ERROR"
    case maintenance = "MAINTENANCE"
    case undefined = "UNDEFINED"
}

struct UnsupportedSchemaVersionError: Error {
    let version: Int
}

struct StatusResponse: Decodable {
    let schemaVersion: Int
    let generatedAt: Date
    let status: StatusNode

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw UnsupportedSchemaVersionError(version: schemaVersion)
        }
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        status = try container.decode(StatusNode.self, forKey: .status)
    }
}

struct StatusNode: Decodable {
    let path: String
    let name: String
    let ownCode: StatusCode
    let code: StatusCode
    let reasons: [String]
    let timestamp: Date
    let frequencySeconds: Int?
    let maintenance: Bool
    let stale: Bool
    let children: [StatusNode]

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case ownCode = "own_code"
        case code
        case reasons
        case timestamp
        case frequencySeconds = "frequency_seconds"
        case maintenance
        case stale
        case children
    }
}

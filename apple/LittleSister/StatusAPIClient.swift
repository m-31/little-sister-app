//
//  StatusAPIClient.swift
//  LittleSister
//

import Foundation

enum APIError: Error {
    case networkUnavailable
    case timeout
    case unauthorized(detail: String?)
    case notFound(detail: String?)
    case serverError(statusCode: Int, detail: String?)
    case invalidResponse
    case unsupportedSchemaVersion(Int)
}

struct StatusAPIClient {

    private let endpointURL: URL
    private let token: String
    private let session: URLSession

    init(baseURL: URL, nodePath: String?, token: String, session: URLSession = .shared) {
        var base = baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        let urlString: String
        if let path = nodePath, !path.isEmpty {
            urlString = "\(base)/status/\(path)"
        } else {
            urlString = "\(base)/status"
        }
        // URL(string:) fails only for truly malformed input; the fallback is unreachable in practice.
        self.endpointURL = URL(string: urlString) ?? baseURL.appendingPathComponent("status")
        self.token = token
        self.session = session
    }

    func fetchStatus() async throws -> StatusResponse {
        let request = buildRequest()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw APIError.timeout
            default:
                throw APIError.networkUnavailable
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try decodeResponse(data)
        case 401:
            throw APIError.unauthorized(detail: problemDetail(from: data))
        case 404:
            throw APIError.notFound(detail: problemDetail(from: data))
        default:
            throw APIError.serverError(statusCode: http.statusCode, detail: problemDetail(from: data))
        }
    }

    // MARK: - Private

    private func buildRequest() -> URLRequest {
        var request = URLRequest(url: endpointURL, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Flow-Id")
        return request
    }

    private func decodeResponse(_ data: Data) throws -> StatusResponse {
        do {
            return try Self.makeDecoder().decode(StatusResponse.self, from: data)
        } catch let e as UnsupportedSchemaVersionError {
            throw APIError.unsupportedSchemaVersion(e.version)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private struct ProblemResponse: Decodable {
        let title: String?
        let detail: String?
    }

    // Attempts to extract a human-readable detail from a Problem JSON body (RFC 9457).
    // Returns nil gracefully when the body is absent, empty, or not valid Problem JSON.
    private func problemDetail(from data: Data) -> String? {
        guard !data.isEmpty,
              let p = try? JSONDecoder().decode(ProblemResponse.self, from: data) else { return nil }
        return p.detail ?? p.title
    }

    // Internal so the test suite can share the canonical date strategy without duplicating it.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(string)"
            )
        }
        return decoder
    }
}

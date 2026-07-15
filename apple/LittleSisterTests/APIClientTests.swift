//
//  APIClientTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    // Serialized suite access makes these safe without a lock.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Shared fixtures and helpers

private let testBaseURL = URL(string: "http://test.example")!

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeClient(nodePath: String? = nil, session: URLSession) -> StatusAPIClient {
    StatusAPIClient(baseURL: testBaseURL, nodePath: nodePath, token: "test-token", session: session)
}

private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private let validResponseData = """
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
        "children": []
    }
}
""".data(using: .utf8)!

// MARK: - Tests

// Serialized because tests share MockURLProtocol's static handler and lastRequest.
@Suite("HTTP Behavior", .serialized)
struct HTTPBehaviorTests {

    // Swift Testing creates a fresh struct instance per test, so each test gets its own session.
    private let session = makeMockSession()
    private var client: StatusAPIClient { makeClient(session: session) }

    @Test("Request sets Accept: application/json")
    func requestSetsAcceptHeader() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 200), validResponseData) }
        _ = try await client.fetchStatus()
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Request sets Authorization bearer token")
    func requestSetsBearerToken() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 200), validResponseData) }
        _ = try await client.fetchStatus()
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("Request sends a non-empty X-Flow-Id that is a valid UUID")
    func requestSendsFlowId() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 200), validResponseData) }
        _ = try await client.fetchStatus()
        let req = try #require(MockURLProtocol.lastRequest)
        let flowId = try #require(req.value(forHTTPHeaderField: "X-Flow-Id"))
        #expect(UUID(uuidString: flowId) != nil)
    }

    @Test("401 produces unauthorized")
    func status401IsUnauthorized() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 401), Data()) }
        do {
            _ = try await client.fetchStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let e as APIError {
            guard case .unauthorized = e else {
                #expect(Bool(false), "Expected .unauthorized, got \(e)"); return
            }
        }
    }

    @Test("404 produces notFound")
    func status404IsNotFound() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 404), Data()) }
        do {
            _ = try await client.fetchStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let e as APIError {
            guard case .notFound = e else {
                #expect(Bool(false), "Expected .notFound, got \(e)"); return
            }
        }
    }

    @Test("Valid Problem JSON detail is surfaced in the error")
    func validProblemJSONDetailSurfaces() async throws {
        let body = """
        {"type":"about:blank","title":"Unauthorized","status":401,"detail":"Token expired"}
        """.data(using: .utf8)!
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 401), body) }
        do {
            _ = try await client.fetchStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let e as APIError {
            guard case .unauthorized(let detail) = e else {
                #expect(Bool(false), "Expected .unauthorized, got \(e)"); return
            }
            #expect(detail == "Token expired")
        }
    }

    @Test("Malformed Problem JSON body still produces a typed error")
    func malformedProblemJSONProducesTypedError() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 401), "not json".data(using: .utf8)!) }
        do {
            _ = try await client.fetchStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let e as APIError {
            guard case .unauthorized = e else {
                #expect(Bool(false), "Expected .unauthorized despite malformed body, got \(e)"); return
            }
        }
    }

    @Test("Malformed success JSON produces invalidResponse")
    func malformedSuccessJSONIsInvalidResponse() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 200), "not json".data(using: .utf8)!) }
        do {
            _ = try await client.fetchStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let e as APIError {
            guard case .invalidResponse = e else {
                #expect(Bool(false), "Expected .invalidResponse, got \(e)"); return
            }
        }
    }

    @Test("URLError.timedOut maps to APIError.timeout")
    func timedOutMapsToTimeout() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await client.fetchStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let e as APIError {
            guard case .timeout = e else {
                #expect(Bool(false), "Expected .timeout, got \(e)"); return
            }
        }
    }

    @Test("Other URLError maps to APIError.networkUnavailable")
    func otherURLErrorMapsToNetworkUnavailable() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.fetchStatus()
            #expect(Bool(false), "Expected error to be thrown")
        } catch let e as APIError {
            guard case .networkUnavailable = e else {
                #expect(Bool(false), "Expected .networkUnavailable, got \(e)"); return
            }
        }
    }

    @Test("Non-nil nodePath produces /status/<path> URL")
    func nodePathProducesStatusPathURL() async throws {
        MockURLProtocol.handler = { req in (httpResponse(url: req.url!, statusCode: 200), validResponseData) }
        let pathClient = makeClient(nodePath: "system/db", session: session)
        _ = try await pathClient.fetchStatus()
        let req = try #require(MockURLProtocol.lastRequest)
        #expect(req.url == URL(string: "http://test.example/status/system/db"))
    }
}

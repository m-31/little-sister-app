//
//  FailureTaxonomyTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

// ADR-0011 §1: a poll can fail in materially different ways, and each one points
// somewhere different — this Mac, the resolver, the route, or the service. These
// tests pin the whole table, mapping and wording together, without a network.
@Suite("Network failure taxonomy")
@MainActor
struct FailureTaxonomyTests {

    private let host = "nas1"

    // The two halves under test, composed the way the app composes them:
    // StatusAPIClient classifies, MonitoringViewModel words it.
    private func reason(for code: URLError.Code, host: String? = "nas1") -> String {
        MonitoringViewModel.errorReason(
            from: StatusAPIClient.apiError(for: URLError(code), host: host))
    }

    @Test("No local network path is named as such")
    func noConnection() {
        #expect(reason(for: .notConnectedToInternet) == "No network connection")
    }

    @Test("Both resolver failures name the host that could not be resolved")
    func resolutionFailuresNameTheHost() {
        #expect(reason(for: .dnsLookupFailed) == "Cannot resolve nas1")
        #expect(reason(for: .cannotFindHost) == "Cannot resolve nas1")
    }

    @Test("A resolved-but-unconnectable host is named, without claiming a refusal")
    func cannotConnectNamesTheHost() {
        #expect(reason(for: .cannotConnectToHost) == "Cannot connect to nas1")
    }

    @Test("A mid-transfer drop is distinguished from having no path at all")
    func connectionLostIsItsOwnReason() {
        #expect(reason(for: .networkConnectionLost) == "Connection lost")
    }

    @Test("A timeout keeps the wording it already had")
    func timeoutWordingIsUnchanged() {
        #expect(reason(for: .timedOut) == "Request timed out")
    }

    // The failure a Settings dialog invites: type a real domain over plain HTTP
    // and macOS refuses before a packet leaves the machine. Reported as a bare
    // "-1022" it is the most confusing failure in the set, because the same URL
    // opens fine in the user's browser.
    @Test("An ATS refusal says what to do about it")
    func atsRefusalNamesTheFix() {
        #expect(reason(for: .appTransportSecurityRequiresSecureConnection)
                == "Plain HTTP is blocked by macOS; use https://")
    }

    @Test("An unparseable HTTP reply is an invalid response, not a network error")
    func badServerResponseIsInvalidResponse() {
        guard case .invalidResponse =
                StatusAPIClient.apiError(for: URLError(.badServerResponse), host: host) else {
            #expect(Bool(false), "Expected .invalidResponse"); return
        }
        #expect(reason(for: .badServerResponse) == "Invalid response")
    }

    @Test("An unnamed URLError keeps its code rather than being flattened")
    func unmappedCodeKeepsItsCode() {
        let code = URLError.Code.secureConnectionFailed
        guard case .networkError(let carried) =
                StatusAPIClient.apiError(for: URLError(code), host: host) else {
            #expect(Bool(false), "Expected .networkError for an unnamed code"); return
        }
        #expect(carried == code.rawValue)
        #expect(reason(for: code) == "Network error (\(code.rawValue))")
    }

    @Test("Each named code maps to its own case, never to the fallback")
    func namedCodesDoNotFallThrough() {
        let named: [URLError.Code] = [
            .notConnectedToInternet, .dnsLookupFailed, .cannotFindHost,
            .cannotConnectToHost, .networkConnectionLost, .timedOut,
            .appTransportSecurityRequiresSecureConnection, .badServerResponse,
        ]
        for code in named {
            if case .networkError = StatusAPIClient.apiError(for: URLError(code), host: host) {
                #expect(Bool(false), "\(code) fell through to .networkError")
            }
        }
    }

    @Test("A URL without a host still yields a readable reason")
    func missingHostnameStillReads() {
        #expect(reason(for: .cannotFindHost, host: nil) == "Cannot resolve the server name")
        #expect(reason(for: .cannotConnectToHost, host: nil) == "Cannot connect to the server")
    }

    // Distinctness is the property the taxonomy exists for: two different
    // failures must not render as the same sentence. (`.dnsLookupFailed` is
    // left out because it deliberately shares wording with `.cannotFindHost`.)
    //
    // Note what this suite does *not* establish: that no reason string can ever
    // carry the bearer token. Every reason here derives from a `URLError`, where
    // the token was never in scope, so such an assertion would pass for free and
    // read far stronger than it is. The one reason built from text this app does
    // not control is `.unauthorized(detail:)`, whose detail comes from the
    // server's Problem JSON; that exposure is tracked in the docs, not here.
    @Test("Every mapped code yields a distinct, non-empty reason")
    func reasonsAreDistinctAndNonEmpty() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost,
            .networkConnectionLost, .timedOut, .secureConnectionFailed,
            .appTransportSecurityRequiresSecureConnection, .badServerResponse,
        ]
        let reasons = codes.map { reason(for: $0) }
        #expect(reasons.allSatisfy { !$0.isEmpty })
        #expect(Set(reasons).count == reasons.count)
    }
}

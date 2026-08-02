//
//  StatusAPIClient.swift
//  LittleSister
//

import Foundation

enum APIError: Error {
    // Network-layer failures. Kept distinct rather than collapsed into one
    // "network unavailable" string, because each points somewhere different:
    // this Mac, the resolver, the route, or the service (ADR-0011 §1).
    case noConnection
    case cannotResolveHost(host: String?)
    // Named for what URLSession actually reports: the name resolved but no
    // connection was established. That covers a refusal, but also a filtered
    // port, an unrouted subnet and a host that is simply down — so the reason
    // string does not claim a refusal it cannot distinguish.
    case cannotConnect(host: String?)
    case connectionLost
    case timeout
    // App Transport Security refused the request before it left this Mac. Not a
    // network condition at all — a configuration one, and the only failure here
    // that no amount of retrying can change.
    case blockedByAppTransportSecurity
    // Any URLError the table above does not name, carrying its code so the
    // information is never silently discarded.
    case networkError(code: Int)

    // HTTP- and payload-level failures: the server answered, or answered wrongly.
    case unauthorized(detail: String?)
    case notFound(detail: String?)
    case serverError(statusCode: Int, detail: String?)
    case invalidResponse
    case unsupportedSchemaVersion(Int)
    // The body parsed as valid JSON and carries a schema_version we understand,
    // but our model no longer matches — a within-version contract change. The
    // detail names the first failing coding path and what was expected.
    case contractMismatch(detail: String)
}

// Whether asking again, unprompted, could plausibly produce a different answer.
enum RetryClass {
    // May heal on its own: the network, or a server that is failing rather than
    // answering. Worth retrying quickly.
    case transient
    // The server answered clearly, or the request never left this Mac. Nothing
    // about repeating it changes the outcome — only the user can.
    case definite
}

extension APIError {

    // Retry-ability is a property of the failure, not a policy of the loop: a
    // 401 is definite for any caller that could ever hold one of these. So it
    // lives here rather than beside the schedule that consumes it — and a case
    // added tomorrow fails the build in this file, in the same edit that added
    // it (ADR-0011 §4).
    //
    // Deliberately no `default`: exhaustiveness is the whole mechanism.
    var retryClass: RetryClass {
        switch self {
        case .noConnection, .cannotResolveHost, .cannotConnect, .connectionLost,
             .timeout, .networkError:
            // The network. Every one of these can come back without anyone
            // touching anything.
            return .transient
        case .serverError:
            // A 5xx is the server *failing*, not answering; the next poll may
            // find it recovered.
            return .transient
        case .invalidResponse:
            // A body truncated by a flaky link is indistinguishable from one the
            // server malformed, so this keeps the benefit of the doubt.
            return .transient
        case .unauthorized, .notFound, .unsupportedSchemaVersion:
            // A correct, definite reply. Retrying a rejected token several times
            // a minute is also the one failure whose repetition costs something
            // at the other end — rate limits, lockouts, a log full of failed
            // authentications.
            return .definite
        case .blockedByAppTransportSecurity:
            // The request never reached the network at all; only a change to the
            // base URL can change this.
            return .definite
        case .contractMismatch:
            // The server answered clearly; only an app or server update changes
            // the outcome. Retrying cannot heal a model that no longer fits.
            return .definite
        }
    }
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

    // `onWaitingForConnectivity` fires when URLSession parks this request because
    // the network path is not viable yet, instead of failing it outright
    // (ADR-0011 §3). It arrives on the session's delegate queue — **not** the main
    // actor — and nothing here hops for the caller; that is the caller's job,
    // which is why the closure is `@Sendable`.
    //
    // Defaulted to a no-op rather than optional so there is exactly one request
    // path: a caller that does not care still runs the same code the app does.
    func fetchStatus(
        onWaitingForConnectivity: @escaping @Sendable () -> Void = {}
    ) async throws -> StatusResponse {
        let request = buildRequest()
        let data: Data
        let response: URLResponse
        do {
            // Per-task, not session-level: `makeSession` explains why this app
            // cannot afford a session delegate (it would be retained until the
            // session is invalidated, once per poll). A per-task delegate is
            // released when its task completes.
            (data, response) = try await session.data(
                for: request,
                delegate: ConnectivityWaitObserver(onWaiting: onWaitingForConnectivity))
        } catch let error as URLError {
            throw Self.apiError(for: error, host: endpointURL.host)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try Self.decodeResponse(data)
        case 401:
            throw APIError.unauthorized(detail: problemDetail(from: data))
        case 404:
            throw APIError.notFound(detail: problemDetail(from: data))
        default:
            throw APIError.serverError(statusCode: http.statusCode, detail: problemDetail(from: data))
        }
    }

    // MARK: - Failure taxonomy

    // Maps what URLSession already knows about a failure onto a reason the menu
    // can act on (ADR-0011 §1). The host name is presentational and safe to
    // show; no error path ever carries the bearer token.
    //
    // Internal and static so the whole table can be tested without a network.
    static func apiError(for error: URLError, host: String?) -> APIError {
        switch error.code {
        case .notConnectedToInternet:
            return .noConnection
        case .dnsLookupFailed, .cannotFindHost:
            return .cannotResolveHost(host: host)
        case .cannotConnectToHost:
            return .cannotConnect(host: host)
        case .networkConnectionLost:
            return .connectionLost
        case .timedOut:
            return .timeout
        case .appTransportSecurityRequiresSecureConnection:
            return .blockedByAppTransportSecurity
        case .badServerResponse:
            // Not a network fault: something answered, but not parseable HTTP.
            // Semantically the invalid-response case the enum already has.
            return .invalidResponse
        default:
            return .networkError(code: error.code.rawValue)
        }
    }

    // MARK: - Timeouts

    // One budget for a whole poll attempt, derived from the only cadence the
    // user ever expressed an opinion about (ADR-0011 §2): 80% of the poll
    // interval, capped at 30s so a very long interval does not license a very
    // long hang.
    //
    // The polling loop sleeps *after* a poll returns, so a timeout longer than
    // the interval quietly overrules the setting: the fixed 30s this replaces
    // turned a 5-second interval into one poll every 35 seconds.
    //
    // The input is clamped to the setting's own minimum, which is the only
    // floor in the expression. The 4 seconds a fast configuration sees is a
    // consequence of that — four fifths of the smallest interval anyone can
    // pick — not a second constant that has to be maintained below the first.
    // That is what makes `budget < pollInterval` arithmetic rather than luck:
    // below the cap the budget is four fifths of a clamped interval, and an
    // interval that reaches the cap has to exceed 37 seconds to get there.
    //
    // Seconds. Pure and static, so the derivation is tested without a network.
    static func timeoutBudget(pollInterval: Int) -> Int {
        let interval = max(AppSettings.minimumPollInterval, pollInterval)
        return min(30, interval * 4 / 5)
    }

    // The idle timeout, which only starts to matter once a connection exists.
    // Deliberately tighter than the budget: the full budget stays available for
    // waiting on a network path — during which the idle timer is not running at
    // all — while a server that accepts the connection and then goes silent is
    // abandoned in half the time. Seconds.
    //
    // No floor of its own. The budget cannot be smaller than 4, so this cannot
    // fall below 2, and writing that 2 down would be the same mistake as the
    // literal floor the budget used to carry: a constant that only restates a
    // consequence, and that would quietly start binding — masking the change —
    // if the cap or the setting's minimum ever moved.
    static func requestTimeout(pollInterval: Int) -> Int {
        timeoutBudget(pollInterval: pollInterval) / 2
    }

    // The session a poll runs on: fresh per poll, because a long-lived one can
    // keep reusing a connection the network already killed.
    //
    // `waitsForConnectivity` is what stops a request made before the OS
    // considers the path ready from failing instantly — and the resource timeout
    // is what bounds that wait, since its default is seven days.
    //
    // Delegate-less on purpose, and fresh-per-poll is why. A session built with
    // `URLSession(configuration:delegate:delegateQueue:)` holds its delegate
    // strongly until the session is invalidated, so a session-level delegate
    // here would strand one object per poll — on the order of 1,400 a day at the
    // default interval. Anything that needs delegate callbacks (ADR-0011 §3's
    // `taskIsWaitingForConnectivity`) has to go through the per-task
    // `session.data(for:delegate:)` overload, whose delegate is released when
    // that task completes.
    static func makeSession(pollInterval: Int) -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        // The whole attempt, including any wait for connectivity.
        config.timeoutIntervalForResource = TimeInterval(timeoutBudget(pollInterval: pollInterval))
        // Idle time with no bytes arriving, once the connection is up.
        config.timeoutIntervalForRequest = TimeInterval(requestTimeout(pollInterval: pollInterval))
        return URLSession(configuration: config)
    }

    // MARK: - Private

    private func buildRequest() -> URLRequest {
        var request = URLRequest(url: endpointURL)
        // Still one source for the number — it is derived in makeSession, and
        // read back off the session that will actually run this request.
        //
        // A bare URLRequest carries its own 60s default, and which of the two
        // wins is not clearly documented. If the request's value won, the idle
        // timeout would silently be 60s — looser than the whole-attempt budget,
        // so the "abandoned in half the time" intent would never happen and
        // nothing would say so. Copying the session's value makes the outcome
        // the same whichever way precedence goes.
        request.timeoutInterval = session.configuration.timeoutIntervalForRequest
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Flow-Id")
        return request
    }

    // Static and internal: makes the decode logic testable without a network,
    // like apiError(for:host:). Effectively only throws APIError — all paths
    // through the catch chain are rethrown as a typed case.
    static func decodeResponse(_ data: Data) throws -> StatusResponse {
        do {
            return try makeDecoder().decode(StatusResponse.self, from: data)
        } catch let e as UnsupportedSchemaVersionError {
            throw APIError.unsupportedSchemaVersion(e.version)
        } catch let decodingError {
            // A body that parses as JSON and carries the envelope is not a
            // truncated body — the server answered coherently and our model no
            // longer fits. Probe for schema_version before deciding (ADR-0011 §4).
            if let probe = try? JSONDecoder().decode(SchemaVersionProbe.self, from: data) {
                if probe.schemaVersion == 1 {
                    // Same-version drift. Only an app or server update can fix this;
                    // retrying will not — which is why this is definite.
                    throw APIError.contractMismatch(detail: decodingDetail(from: decodingError))
                } else {
                    // A different version that slipped past StatusResponse.init's
                    // guard — normally unreachable, kept so the probe is total.
                    throw APIError.unsupportedSchemaVersion(probe.schemaVersion)
                }
            }
            // Probe failed: not valid JSON, or envelope missing. Could be a
            // truncated body — keep the benefit of the doubt.
            throw APIError.invalidResponse
        }
    }

    private struct SchemaVersionProbe: Decodable {
        let schemaVersion: Int
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
        }
    }

    private static func decodingDetail(from error: Error) -> String {
        guard let de = error as? DecodingError else { return error.localizedDescription }
        switch de {
        case .keyNotFound(let key, let ctx):
            let path = (ctx.codingPath + [key]).map { $0.stringValue }.joined(separator: ".")
            return "\(path) — key not found"
        case .valueNotFound(_, let ctx):
            return "\(codingPath(ctx)) — value not found"
        case .typeMismatch(_, let ctx):
            return "\(codingPath(ctx)) — type mismatch"
        case .dataCorrupted(let ctx):
            return "\(codingPath(ctx)) — data corrupted"
        default:
            return de.localizedDescription
        }
    }

    private static func codingPath(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map { $0.stringValue }.joined(separator: ".")
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

// MARK: - Waiting for connectivity

// The per-task delegate behind `fetchStatus(onWaitingForConnectivity:)`.
//
// `nonisolated` deliberately: URLSession calls this on the session's delegate
// queue, so a main-actor-isolated conformance would be one this framework can
// never use. `@unchecked Sendable` is safe for the same reason it is necessary —
// the only stored property is an immutable `@Sendable` closure, and NSObject
// simply cannot carry the conformance on its own.
//
// Worth knowing before editing: `taskIsWaitingForConnectivity` is an *optional*
// `@objc` requirement, so a signature that drifts by one label stops being
// called without anything failing to compile. Nothing in the test suite can
// catch that — the callback fires only when there is no viable network path,
// which a working process cannot arrange — so it is verified by running the app
// with the network off and watching the Debug Log.
private nonisolated final class ConnectivityWaitObserver:
        NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    private let onWaiting: @Sendable () -> Void

    init(onWaiting: @escaping @Sendable () -> Void) {
        self.onWaiting = onWaiting
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        onWaiting()
    }
}

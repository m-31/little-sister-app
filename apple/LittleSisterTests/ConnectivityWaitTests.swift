//
//  ConnectivityWaitTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

// MARK: - A stub that holds the request open

// Every request parks until the test releases it, which turns "while a poll is
// in flight" into a moment the test controls rather than a race against an
// instant loopback answer.
//
// What it deliberately does *not* do is provoke the real callback.
// `taskIsWaitingForConnectivity` fires only when URLSession has no viable path
// to the host, which a running process cannot arrange for itself — so these
// tests stand in for the delegate by calling the view model's own entry point
// at the moment the delegate would have called it. That pins what the app does
// with a wait; that URLSession reports one is verified by running the app with
// the network off.
final class WaitMockURLProtocol: URLProtocol {
    // A serialized suite plus a fresh semaphore per test keeps this safe;
    // `wait()` blocks a session-owned background thread, never the main actor.
    nonisolated(unsafe) static var released = DispatchSemaphore(value: 0)
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.released.wait()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let healthyBody = """
{"schema_version":1,"generated_at":"2026-06-25T18:05:00Z","status":{"path":"/","name":"root","own_code":"OK","code":"OK","reasons":[],"timestamp":"2026-06-25T18:04:55Z","maintenance":false,"stale":false,"children":[]}}
""".data(using: .utf8)!

// MARK: - Tests

// Serialized because every test in here drives the same stubbed protocol class.
@Suite("Waiting for connectivity", .serialized)
@MainActor
struct ConnectivityWaitTests {

    private let spy = NotificationSpy()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [WaitMockURLProtocol.self]
        return URLSession(configuration: cfg)
    }()

    private func makeVM() -> MonitoringViewModel {
        WaitMockURLProtocol.released = DispatchSemaphore(value: 0)
        WaitMockURLProtocol.body = healthyBody
        let session = self.session
        return MonitoringViewModel(
            clientProvider: {
                StatusAPIClient(
                    baseURL: URL(string: "http://test.example")!,
                    nodePath: nil,
                    token: "tok",
                    session: session
                )
            },
            notificationSender: spy
        )
    }

    // Lets the parked request answer.
    private func release() { WaitMockURLProtocol.released.signal() }

    // The token the running poll handed to its delegate. Bounded rather than a
    // `while` loop, so a mistake fails this test instead of hanging the suite.
    private func inFlightToken(of vm: MonitoringViewModel) async -> Int? {
        for _ in 0..<1_000 {
            if let token = vm.inFlightPoll { return token }
            await Task.yield()
        }
        return nil
    }

    // The load-bearing constraint of ADR-0011 §3: a wait changes what the menu
    // says and nothing else. If it reached `applyState(_:)` a two-second hiccup
    // would emit a notification pair, which is worse than the frozen-looking
    // menu the flag exists to explain.
    @Test("A wait raises the flag without touching state or notifications")
    func waitIsPresentationalOnly() async throws {
        let vm = makeVM()
        release()
        await vm.poll()                      // a completed poll, so there is a state to disturb
        spy.sent.removeAll()
        let stateBefore = vm.displayState

        let polling = Task { await vm.poll() }
        let token = try #require(await inFlightToken(of: vm))
        vm.noteWaitingForNetwork(token: token)

        #expect(vm.isWaitingForNetwork)
        #expect(vm.displayState == stateBefore)
        #expect(spy.sent.isEmpty)

        release()
        await polling.value
        #expect(vm.isWaitingForNetwork == false)   // the wait ended when the request did
    }

    @Test("A callback that outlives its own poll cannot raise the flag")
    func lateCallbackIsIgnored() async throws {
        let vm = makeVM()
        let polling = Task { await vm.poll() }
        let token = try #require(await inFlightToken(of: vm))
        release()
        await polling.value

        vm.noteWaitingForNetwork(token: token)     // the hop landed after the request finished
        #expect(vm.isWaitingForNetwork == false)
    }

    // The case the token exists for that a plain "is a poll running?" check
    // would get wrong: a late callback from poll N arriving while poll N+1 is
    // in flight would otherwise be believed.
    @Test("A callback from an earlier poll cannot raise the flag during a later one")
    func callbackFromEarlierPollIsIgnored() async throws {
        let vm = makeVM()
        let first = Task { await vm.poll() }
        let firstToken = try #require(await inFlightToken(of: vm))
        release()
        await first.value

        let second = Task { await vm.poll() }
        let secondToken = try #require(await inFlightToken(of: vm))
        #expect(secondToken != firstToken)

        vm.noteWaitingForNetwork(token: firstToken)
        #expect(vm.isWaitingForNetwork == false)

        release()
        await second.value
    }

    // Nothing outside a poll may raise it either: with no request in flight
    // there is no wait, and no code path that would ever lower the flag again.
    @Test("With no poll in flight, no token is accepted")
    func noTokenIsAcceptedWhenIdle() async {
        let vm = makeVM()
        release()
        await vm.poll()

        #expect(vm.inFlightPoll == nil)
        for token in [0, 1, 2, 99] {
            vm.noteWaitingForNetwork(token: token)
        }
        #expect(vm.isWaitingForNetwork == false)
    }
}

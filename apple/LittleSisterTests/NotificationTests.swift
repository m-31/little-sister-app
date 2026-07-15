//
//  NotificationTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

@Suite("Notifications")
struct NotificationTests {

    // MARK: - No prior state

    @Test("nil from produces no notification for any to-state")
    func nilFromNeverNotifies() {
        #expect(notification(from: nil, to: .healthy) == nil)
        #expect(notification(from: nil, to: .warning(isStale: false)) == nil)
        #expect(notification(from: nil, to: .error) == nil)
        #expect(notification(from: nil, to: .maintenance) == nil)
        #expect(notification(from: nil, to: .unavailable(reason: "x")) == nil)
    }

    // MARK: - Same-case (no notification)

    @Test("Repeated ERROR responses do not notify again")
    func repeatedErrorDoesNotNotify() {
        #expect(notification(from: .error, to: .error) == nil)
    }

    @Test("Repeated healthy does not notify")
    func repeatedHealthyDoesNotNotify() {
        #expect(notification(from: .healthy, to: .healthy) == nil)
    }

    @Test("Stale transition does not notify when case stays warning")
    func staleTransitionDoesNotNotify() {
        #expect(notification(from: .warning(isStale: false), to: .warning(isStale: true)) == nil)
        #expect(notification(from: .warning(isStale: true), to: .warning(isStale: false)) == nil)
    }

    @Test("undefined/unavailable reason change does not notify")
    func unavailableReasonChangeDoesNotNotify() {
        #expect(notification(from: .unavailable(reason: "old"), to: .unavailable(reason: "new")) == nil)
        #expect(notification(from: .undefined(reason: "old"), to: .undefined(reason: "new")) == nil)
    }

    @Test("undefined → unavailable does not notify (same logical case)")
    func undefinedToUnavailableDoesNotNotify() {
        #expect(notification(from: .undefined(reason: "server said so"), to: .unavailable(reason: "network gone")) == nil)
        #expect(notification(from: .unavailable(reason: "network gone"), to: .undefined(reason: "server said so")) == nil)
    }

    // MARK: - Named transitions

    @Test("healthy → warning notifies with warning wording")
    func healthyToWarning() {
        let n = notification(from: .healthy, to: .warning(isStale: false))
        #expect(n?.title == "Monitoring warning")
    }

    @Test("healthy → warning(isStale: true) also notifies with warning wording")
    func healthyToStaleWarning() {
        let n = notification(from: .healthy, to: .warning(isStale: true))
        #expect(n?.title == "Monitoring warning")
    }

    @Test("Transition to error notifies once")
    func healthyToError() {
        let n = notification(from: .healthy, to: .error)
        #expect(n?.title == "Monitoring error")
    }

    @Test("warning → error notifies with error wording")
    func warningToError() {
        let n = notification(from: .warning(isStale: false), to: .error)
        #expect(n?.title == "Monitoring error")
    }

    @Test("Error-to-healthy recovery notifies")
    func errorToHealthy() {
        let n = notification(from: .error, to: .healthy)
        #expect(n?.title == "Service recovered")
    }

    @Test("error → maintenance notifies with maintenance wording")
    func errorToMaintenance() {
        let n = notification(from: .error, to: .maintenance)
        #expect(n?.title == "Monitoring placed in maintenance")
    }

    @Test("maintenance → error notifies with unhealthy wording")
    func maintenanceToError() {
        let n = notification(from: .maintenance, to: .error)
        #expect(n?.title == "Maintenance ended; service is unhealthy")
    }

    @Test("any → unavailable notifies with unavailable wording")
    func anyToUnavailable() {
        let froms: [DisplayState] = [
            .healthy,
            .warning(isStale: false),
            .warning(isStale: true),
            .error,
            .maintenance,
        ]
        for from in froms {
            let n = notification(from: from, to: .unavailable(reason: "test"))
            #expect(n?.title == "Monitoring status unavailable", "expected unavailable from \(from)")
        }
    }

    @Test("any → undefined also notifies with unavailable wording")
    func anyToUndefined() {
        let froms: [DisplayState] = [
            .healthy,
            .warning(isStale: false),
            .error,
            .maintenance,
        ]
        for from in froms {
            let n = notification(from: from, to: .undefined(reason: "test"))
            #expect(n?.title == "Monitoring status unavailable", "expected unavailable from \(from)")
        }
    }

    @Test("unavailable → healthy notifies with available-again wording")
    func unavailableToHealthy() {
        let n = notification(from: .unavailable(reason: "test"), to: .healthy)
        #expect(n?.title == "Monitoring status available again")
    }

    @Test("undefined → healthy also notifies with available-again wording")
    func undefinedToHealthy() {
        let n = notification(from: .undefined(reason: "test"), to: .healthy)
        #expect(n?.title == "Monitoring status available again")
    }

    @Test("unavailable → error notifies with error wording")
    func unavailableToError() {
        let n = notification(from: .unavailable(reason: "test"), to: .error)
        #expect(n?.title == "Monitoring error")
    }

    // MARK: - Generic fallback

    @Test("warning → healthy uses generic wording")
    func warningToHealthy() {
        let n = notification(from: .warning(isStale: false), to: .healthy)
        #expect(n?.title == "Monitoring: ok")
    }

    @Test("error → warning uses generic wording")
    func errorToWarning() {
        let n = notification(from: .error, to: .warning(isStale: false))
        #expect(n?.title == "Monitoring: warn")
    }

    @Test("error → warning(isStale: true) uses label with stale qualifier")
    func errorToStaleWarning() {
        let n = notification(from: .error, to: .warning(isStale: true))
        #expect(n?.title == "Monitoring: warn (stale)")
    }

    @Test("healthy → maintenance uses generic wording")
    func healthyToMaintenance() {
        let n = notification(from: .healthy, to: .maintenance)
        #expect(n?.title == "Monitoring: maintenance")
    }

    @Test("maintenance → healthy uses generic wording")
    func maintenanceToHealthy() {
        let n = notification(from: .maintenance, to: .healthy)
        #expect(n?.title == "Monitoring: ok")
    }

    @Test("unavailable → warning uses generic wording")
    func unavailableToWarning() {
        let n = notification(from: .unavailable(reason: "x"), to: .warning(isStale: false))
        #expect(n?.title == "Monitoring: warn")
    }

    @Test("unavailable → maintenance uses generic wording")
    func unavailableToMaintenance() {
        let n = notification(from: .unavailable(reason: "x"), to: .maintenance)
        #expect(n?.title == "Monitoring: maintenance")
    }

    @Test("maintenance → warning uses generic wording")
    func maintenanceToWarning() {
        let n = notification(from: .maintenance, to: .warning(isStale: false))
        #expect(n?.title == "Monitoring: warn")
    }

    @Test("warning → maintenance uses generic wording")
    func warningToMaintenance() {
        let n = notification(from: .warning(isStale: false), to: .maintenance)
        #expect(n?.title == "Monitoring: maintenance")
    }
}

// MARK: - Spy

final class NotificationSpy: NotificationSending, @unchecked Sendable {
    private(set) var authorizationRequested = false
    var sent: [(title: String, body: String, isAlert: Bool)] = []
    private(set) var alarmsPlayed: [String] = []
    var alarmFileURLsPlayed: [URL] = []

    func requestAuthorization() async { authorizationRequested = true }
    func send(title: String, body: String, isAlert: Bool) async {
        sent.append((title: title, body: body, isAlert: isAlert))
    }
    var stubbedAlarmDuration: TimeInterval = 0

    @discardableResult
    func playAlarm(soundName: String) -> TimeInterval {
        alarmsPlayed.append(soundName)
        return stubbedAlarmDuration
    }

    @discardableResult
    func playAlarm(fileURL: URL) -> TimeInterval {
        alarmFileURLsPlayed.append(fileURL)
        return stubbedAlarmDuration
    }
}

// MARK: - Dedicated URLProtocol for integration tests
//
// A separate class with its own static handler avoids any interference with
// MockURLProtocol (used by HTTPBehaviorTests), which lets both suites run
// concurrently without corrupting each other's shared static state.

final class NotificationMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = NotificationMockURLProtocol.handler else {
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

// MARK: - Integration: MonitoringViewModel + spy

// Serialized because NotificationMockURLProtocol.handler is a shared static.
@Suite("Notification Integration", .serialized)
@MainActor
struct NotificationIntegrationTests {

    private let spy = NotificationSpy()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [NotificationMockURLProtocol.self]
        return URLSession(configuration: cfg)
    }()

    private func makeVM() -> MonitoringViewModel {
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

    private func respond(code: String, stale: Bool = false, statusCode: Int = 200) {
        let body = """
        {"schema_version":1,"generated_at":"2026-06-25T18:05:00Z","status":{"path":"/","name":"root","own_code":"\(code)","code":"\(code)","reasons":[],"timestamp":"2026-06-25T18:04:55Z","maintenance":false,"stale":\(stale),"children":[]}}
        """.data(using: .utf8)!
        NotificationMockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    @Test("Transition to error notifies once")
    func transitionToErrorNotifiesOnce() async {
        let vm = makeVM()

        respond(code: "OK")
        await vm.poll()                     // first poll — startup notification
        spy.sent.removeAll()

        respond(code: "ERROR")
        await vm.poll()                     // healthy → error
        #expect(spy.sent.count == 1)
        #expect(spy.sent[0].title == "Monitoring error")
    }

    @Test("Repeated ERROR responses do not notify again")
    func repeatedErrorDoesNotNotify() async {
        let vm = makeVM()

        respond(code: "ERROR")
        await vm.poll()                     // first poll — startup notification
        spy.sent.removeAll()

        await vm.poll()                     // error → error (same case)
        #expect(spy.sent.isEmpty)
    }

    @Test("Error-to-healthy recovery notifies")
    func errorToHealthyNotifies() async {
        let vm = makeVM()

        respond(code: "ERROR")
        await vm.poll()                     // first poll — startup notification
        spy.sent.removeAll()

        respond(code: "OK")
        await vm.poll()                     // error → healthy
        #expect(spy.sent.count == 1)
        #expect(spy.sent[0].title == "Service recovered")
    }

    @Test("Error transition sends isAlert: true")
    func errorTransitionSendsIsAlertTrue() async {
        let vm = makeVM()

        respond(code: "OK")
        await vm.poll()                     // first poll — startup notification
        spy.sent.removeAll()

        respond(code: "ERROR")
        await vm.poll()                     // healthy → error
        #expect(spy.sent.count == 1)
        #expect(spy.sent[0].isAlert == true)
    }

    @Test("Non-error transition sends isAlert: false")
    func nonErrorTransitionSendsIsAlertFalse() async {
        let vm = makeVM()

        respond(code: "ERROR")
        await vm.poll()                     // first poll — startup notification
        spy.sent.removeAll()

        respond(code: "OK")
        await vm.poll()                     // error → healthy
        #expect(spy.sent.count == 1)
        #expect(spy.sent[0].isAlert == false)
    }

    @Test("Stale OK does not notify when coming from WARN (same case)")
    func staleTransitionDoesNotNotify() async {
        let vm = makeVM()

        respond(code: "WARN")
        await vm.poll()                     // first poll — startup notification
        spy.sent.removeAll()

        // OK+stale → warning(isStale:true) — same .warning case as WARN
        respond(code: "OK", stale: true)
        await vm.poll()
        #expect(spy.sent.isEmpty)
    }

    @Test("First poll sends a startup notification")
    func firstPollSendsStartupNotification() async {
        let vm = makeVM()

        respond(code: "OK")
        await vm.poll()
        #expect(spy.sent.count == 1)
        #expect(spy.sent[0].title == "Little Sister started")
    }

    @Test("Startup already in error still alerts")
    func startupAlreadyInErrorAlerts() async {
        let vm = makeVM()

        respond(code: "ERROR")
        await vm.poll()
        #expect(spy.sent.count == 1)
        #expect(spy.sent[0].isAlert == true)
    }
}

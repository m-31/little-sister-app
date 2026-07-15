//
//  SettingsTests.swift
//  LittleSisterTests
//

import Testing
import Foundation
@testable import LittleSister

// MARK: - In-memory token store (fake for testing)

final class InMemoryTokenStore: TokenStoring {
    private var stored: String?

    func loadToken() -> String? { stored }
    func save(token: String) { stored = token }
    func deleteToken() { stored = nil }
}

// MARK: - Token storing tests (exercised via the in-memory fake)

@Suite("Token Storing")
struct TokenStoringTests {

    @Test("loadToken returns nil when nothing has been saved")
    func loadNilInitially() {
        #expect(InMemoryTokenStore().loadToken() == nil)
    }

    @Test("save then load round-trips the token")
    func saveAndLoadRoundTrip() {
        let store = InMemoryTokenStore()
        store.save(token: "my-secret-token")
        #expect(store.loadToken() == "my-secret-token")
    }

    @Test("save overwrites an existing token")
    func saveOverwrites() {
        let store = InMemoryTokenStore()
        store.save(token: "old-token")
        store.save(token: "new-token")
        #expect(store.loadToken() == "new-token")
    }

    @Test("deleteToken clears the stored value")
    func deleteClears() {
        let store = InMemoryTokenStore()
        store.save(token: "token")
        store.deleteToken()
        #expect(store.loadToken() == nil)
    }

    @Test("deleteToken is a no-op when nothing is stored")
    func deleteWhenEmpty() {
        let store = InMemoryTokenStore()
        store.deleteToken()
        #expect(store.loadToken() == nil)
    }
}

// MARK: - App settings tests

@Suite("App Settings")
struct AppSettingsTests {

    // Each test gets a fresh, isolated UserDefaults suite so tests never share state.
    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    // MARK: Base URL

    @Test("baseURL defaults to http://localhost:8000 when unset")
    func baseURLDefault() {
        #expect(makeSettings().baseURL == AppSettings.defaultBaseURL)
    }

    @Test("baseURL round-trips")
    func baseURLRoundTrip() {
        let settings = makeSettings()
        settings.baseURL = URL(string: "http://example.com:9000")!
        #expect(settings.baseURL == URL(string: "http://example.com:9000")!)
    }

    // MARK: Node path

    @Test("nodePath defaults to nil when unset")
    func nodePathDefault() {
        #expect(makeSettings().nodePath == nil)
    }

    @Test("nodePath round-trips a non-empty value")
    func nodePathRoundTrip() {
        let settings = makeSettings()
        settings.nodePath = "system/db"
        #expect(settings.nodePath == "system/db")
    }

    @Test("nodePath set to empty string reads back as nil")
    func nodePathEmptyStringIsNil() {
        let settings = makeSettings()
        settings.nodePath = ""
        #expect(settings.nodePath == nil)
    }

    @Test("nodePath set to nil reads back as nil")
    func nodePathNilIsNil() {
        let settings = makeSettings()
        settings.nodePath = "system/db"
        settings.nodePath = nil
        #expect(settings.nodePath == nil)
    }

    @Test("bare \"/\" normalizes to nil")
    func nodePathBareSlashIsNil() {
        let settings = makeSettings()
        settings.nodePath = "/"
        #expect(settings.nodePath == nil)
    }

    @Test("leading \"/\" is stripped")
    func nodePathLeadingSlashStripped() {
        let settings = makeSettings()
        settings.nodePath = "/system/db"
        #expect(settings.nodePath == "system/db")
    }

    @Test("trailing \"/\" is stripped")
    func nodePathTrailingSlashStripped() {
        let settings = makeSettings()
        settings.nodePath = "system/db/"
        #expect(settings.nodePath == "system/db")
    }

    // MARK: Poll interval

    @Test("pollInterval defaults to 60 when unset")
    func pollIntervalDefault() {
        #expect(makeSettings().pollInterval == AppSettings.defaultPollInterval)
    }

    @Test("pollInterval round-trips")
    func pollIntervalRoundTrip() {
        let settings = makeSettings()
        settings.pollInterval = 30
        #expect(settings.pollInterval == 30)
    }

    // MARK: Sound on error

    @Test("soundOnError defaults to true when unset")
    func soundOnErrorDefault() {
        #expect(makeSettings().soundOnError == true)
    }

    @Test("soundOnError round-trips false")
    func soundOnErrorRoundTripFalse() {
        let settings = makeSettings()
        settings.soundOnError = false
        #expect(settings.soundOnError == false)
    }

    @Test("soundOnError round-trips back to true")
    func soundOnErrorRoundTripTrue() {
        let settings = makeSettings()
        settings.soundOnError = false
        settings.soundOnError = true
        #expect(settings.soundOnError == true)
    }

    // MARK: Modal alert on error

    @Test("modalAlertOnError defaults to true when unset")
    func modalAlertOnErrorDefault() {
        #expect(makeSettings().modalAlertOnError == true)
    }

    @Test("modalAlertOnError round-trips false")
    func modalAlertOnErrorRoundTripFalse() {
        let settings = makeSettings()
        settings.modalAlertOnError = false
        #expect(settings.modalAlertOnError == false)
    }

    @Test("modalAlertOnError round-trips back to true")
    func modalAlertOnErrorRoundTripTrue() {
        let settings = makeSettings()
        settings.modalAlertOnError = false
        settings.modalAlertOnError = true
        #expect(settings.modalAlertOnError == true)
    }
}

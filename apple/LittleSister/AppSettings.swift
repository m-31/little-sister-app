//
//  AppSettings.swift
//  LittleSister
//

import Foundation

struct AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let defaultBaseURL = URL(string: "http://localhost:8000")!
    static let defaultPollInterval = 60

    static let defaultAlarmSoundName = "little-sister_voice"

    // (label, name) pairs for the two bundled sounds. `name` is what's persisted
    // and what NSSound(named:) resolves; `label` is what's shown.
    static let bundledAlarmSounds: [(label: String, name: String)] = [
        ("Little Sister — voice (default)", "little-sister_voice"),
        ("Little Sister — short beep", "little-sister_alarm"),
    ]

    // The fourteen sounds macOS ships in /System/Library/Sounds, matching what
    // System Settings → Sound → Alert sound offers. NSSound(named:) resolves these
    // by name with no bundling required.
    static let systemAlertSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    // (label, name) pairs for the Settings picker. `name` is what's persisted and what
    // NSSound(named:) resolves; `label` is what's shown.
    static let alarmSoundOptions: [(label: String, name: String)] =
        bundledAlarmSounds + systemAlertSoundNames.map { ($0, $0) }

    var baseURL: URL {
        get {
            defaults.string(forKey: Keys.baseURL).flatMap(URL.init) ?? Self.defaultBaseURL
        }
        nonmutating set {
            defaults.set(newValue.absoluteString, forKey: Keys.baseURL)
        }
    }

    // Stored values are always slash-free at both ends (e.g. "system/db", never
    // "/system/db" or "system/db/"). Empty string and nil both mean "use the root
    // endpoint" and are stored as absent (key removed).
    var nodePath: String? {
        get {
            let value = defaults.string(forKey: Keys.nodePath)
            return (value?.isEmpty == false) ? value : nil
        }
        nonmutating set {
            let normalized = newValue?
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .trimmingCharacters(in: .whitespaces)
            if let path = normalized, !path.isEmpty {
                defaults.set(path, forKey: Keys.nodePath)
            } else {
                defaults.removeObject(forKey: Keys.nodePath)
            }
        }
    }

    var pollInterval: Int {
        get {
            let stored = defaults.integer(forKey: Keys.pollInterval)
            // integer(forKey:) returns 0 for unset keys; treat that as "use default".
            return stored > 0 ? stored : Self.defaultPollInterval
        }
        nonmutating set {
            defaults.set(newValue, forKey: Keys.pollInterval)
        }
    }

    // object(forKey:) as? Bool rather than bool(forKey:) — the latter returns false for
    // unset keys, making "default true" impossible to distinguish from "explicitly false".
    var soundOnError: Bool {
        get { defaults.object(forKey: Keys.soundOnError) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Keys.soundOnError) }
    }

    var modalAlertOnError: Bool {
        get { defaults.object(forKey: Keys.modalAlertOnError) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Keys.modalAlertOnError) }
    }

    var alarmSoundName: String {
        get { defaults.string(forKey: Keys.alarmSoundName) ?? AppSettings.defaultAlarmSoundName }
        nonmutating set { defaults.set(newValue, forKey: Keys.alarmSoundName) }
    }

    var repeatAlarmSound: Bool {
        get { defaults.object(forKey: Keys.repeatAlarmSound) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Keys.repeatAlarmSound) }
    }

    var useCustomAlarmSound: Bool {
        get { defaults.object(forKey: Keys.useCustomAlarmSound) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Keys.useCustomAlarmSound) }
    }

    var customAlarmSoundPath: String? {
        get { defaults.string(forKey: Keys.customAlarmSoundPath) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.customAlarmSoundPath)
            } else {
                defaults.removeObject(forKey: Keys.customAlarmSoundPath)
            }
        }
    }

    // Mirrors StatusAPIClient's URL construction — strips trailing slash from base,
    // appends /status or /status/<path>. No token; browser uses session-cookie auth.
    var dashboardURL: URL {
        var base = baseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        if let path = nodePath, !path.isEmpty {
            return URL(string: "\(base)/status/\(path)") ?? baseURL.appendingPathComponent("status")
        }
        return URL(string: "\(base)/status") ?? baseURL.appendingPathComponent("status")
    }

    private enum Keys {
        static let baseURL = "LittleSister.baseURL"
        static let nodePath = "LittleSister.nodePath"
        static let pollInterval = "LittleSister.pollInterval"
        static let soundOnError = "LittleSister.soundOnError"
        static let modalAlertOnError = "LittleSister.modalAlertOnError"
        static let alarmSoundName = "LittleSister.alarmSoundName"
        static let repeatAlarmSound = "LittleSister.repeatAlarmSound"
        static let useCustomAlarmSound = "LittleSister.useCustomAlarmSound"
        static let customAlarmSoundPath = "LittleSister.customAlarmSoundPath"
    }
}

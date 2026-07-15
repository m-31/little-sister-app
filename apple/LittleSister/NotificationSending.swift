//
//  NotificationSending.swift
//  LittleSister
//

import AppKit
import UserNotifications

protocol NotificationSending {
    func requestAuthorization() async
    func send(title: String, body: String, isAlert: Bool) async
    @discardableResult func playAlarm(soundName: String) -> TimeInterval
    @discardableResult func playAlarm(fileURL: URL) -> TimeInterval
}

final class LiveNotificationSender: NSObject, NotificationSending {
    override init() {
        super.init()
        // Without a delegate, UNUserNotificationCenter silently suppresses notifications
        // (including sound) while the app is in the foreground. Setting self as delegate
        // and returning presentation options from willPresent opts in explicitly.
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func send(title: String, body: String, isAlert: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        if isAlert {
            // .timeSensitive breaks through Focus/Do Not Disturb for the visual banner.
            // Sound is handled separately via playAlarm so content.sound is intentionally nil.
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    @discardableResult
    func playAlarm(soundName: String) -> TimeInterval {
        guard let sound = NSSound(named: soundName) else { return 0 }
        sound.play()
        return sound.duration
    }

    @discardableResult
    func playAlarm(fileURL: URL) -> TimeInterval {
        guard let sound = NSSound(contentsOf: fileURL, byReference: true) else { return 0 }
        sound.play()
        return sound.duration
    }
}

extension LiveNotificationSender: UNUserNotificationCenterDelegate {
    // Called by the system when a notification arrives while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

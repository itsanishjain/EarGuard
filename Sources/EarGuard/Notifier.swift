import Foundation
import UserNotifications

final class Notifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("EarGuard notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                NSLog("EarGuard notification authorization denied")
            }
        }
    }

    func sendLoudListeningWarning() {
        let content = UNMutableNotificationContent()
        content.title = "Loud listening"
        content.body = "You've been listening loud for 25 of the last 30 minutes. Consider turning it down."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "earguard.loud-listening.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("EarGuard notification failed: \(error.localizedDescription)")
            }
        }
    }
}

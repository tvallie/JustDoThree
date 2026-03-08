import Foundation
import UserNotifications

/// Manages morning and evening reminder notifications.
final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    // MARK: - Keys

    private let morningEnabledKey  = "jdt_morningEnabled"
    private let eveningEnabledKey  = "jdt_eveningEnabled"
    private let morningHourKey     = "jdt_morningHour"
    private let morningMinuteKey   = "jdt_morningMinute"
    private let eveningHourKey     = "jdt_eveningHour"
    private let eveningMinuteKey   = "jdt_eveningMinute"

    // MARK: - Defaults

    var morningEnabled: Bool {
        get { UserDefaults.standard.object(forKey: morningEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: morningEnabledKey); reschedule() }
    }

    var eveningEnabled: Bool {
        get { UserDefaults.standard.object(forKey: eveningEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: eveningEnabledKey); reschedule() }
    }

    var morningHour: Int {
        get { UserDefaults.standard.object(forKey: morningHourKey) as? Int ?? 8 }
        set { UserDefaults.standard.set(newValue, forKey: morningHourKey); reschedule() }
    }

    var morningMinute: Int {
        get { UserDefaults.standard.object(forKey: morningMinuteKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: morningMinuteKey); reschedule() }
    }

    var eveningHour: Int {
        get { UserDefaults.standard.object(forKey: eveningHourKey) as? Int ?? 19 }
        set { UserDefaults.standard.set(newValue, forKey: eveningHourKey); reschedule() }
    }

    var eveningMinute: Int {
        get { UserDefaults.standard.object(forKey: eveningMinuteKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: eveningMinuteKey); reschedule() }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Scheduling

    func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["jdt_morning", "jdt_evening"])

        // Check authorization status before attempting to schedule
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            if self.morningEnabled {
                self.schedule(
                    id: "jdt_morning",
                    title: "Just Do Three",
                    body: "What are your three today?",
                    hour: self.morningHour,
                    minute: self.morningMinute
                )
            }
            if self.eveningEnabled {
                self.schedule(
                    id: "jdt_evening",
                    title: "Just Do Three",
                    body: "Did you finish your three?",
                    hour: self.eveningHour,
                    minute: self.eveningMinute
                )
            }
        }
    }

    private func schedule(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

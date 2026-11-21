import Foundation
import UserNotifications
import AudioToolbox
import UIKit

enum NotificationManager {
    /// Godzina, o której "przypada" płatność (punkt odniesienia dla odliczania).
    static let dueHour = 9

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Planuje przypomnienia o najbliższych płatnościach.
    /// - Parameter hoursBefore: ile godzin przed płatnością ma przyjść powiadomienie
    ///   (0 = w momencie płatności, 24 = dzień wcześniej o tej samej porze itd.).
    static func reschedule(_ subs: [Subscription],
                           enabled: Bool,
                           hoursBefore: Int,
                           money: (Double) -> String) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        let hours = max(0, hoursBefore)
        let cal = AppCal.cal
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 120, to: start) else { return }

        let when = whenText(hoursBefore: hours)

        for sub in subs {
            for date in sub.occurrences(from: start, to: end).prefix(3) {
                // Moment płatności = dzień płatności o godzinie dueHour
                guard let due = cal.date(bySettingHour: dueHour, minute: 0, second: 0, of: date),
                      let fire = cal.date(byAdding: .hour, value: -hours, to: due),
                      fire > .now else { continue }

                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)

                let content = UNMutableNotificationContent()
                content.title = String(localized: "Zbliża się płatność", bundle: .appLanguage)
                content.body = String(localized: "\(sub.name): \(money(sub.price)) – \(when)", bundle: .appLanguage)
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "\(sub.id.uuidString)-\(Int(date.timeIntervalSince1970))"
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: - Teksty

    private static func whenText(hoursBefore h: Int) -> String {
        switch h {
        case 0:  return String(localized: "dziś", bundle: .appLanguage)
        case 24: return String(localized: "jutro", bundle: .appLanguage)
        default:
            // „za 3 dni” / „in 3 days”, „za 2 godziny” / „in 2 hours” (odmiana w Plural)
            let amount = h % 24 == 0 ? Plural.days(h / 24) : Plural.hours(h)
            return String(localized: "za \(amount)", bundle: .appLanguage)
        }
    }
}

enum SoundManager {
    /// Krótki sygnał potwierdzający kluczową akcję (np. dodanie subskrypcji).
    static func success(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1057)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1104)
    }
}

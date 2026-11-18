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
                content.title = "Zbliża się płatność"
                content.body = "\(sub.name): \(money(sub.price)) – \(when)"
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
        case 0:  return "dziś"
        case 24: return "jutro"
        default:
            if h % 24 == 0 { return "za \(h / 24) dni" }
            return "za \(hoursPhrase(h))"
        }
    }

    /// Polska odmiana: 1 godzinę, 2–4 godziny, 5+ godzin.
    private static func hoursPhrase(_ h: Int) -> String {
        if h == 1 { return "1 godzinę" }
        let n10 = h % 10, n100 = h % 100
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "\(h) godziny" }
        return "\(h) godzin"
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

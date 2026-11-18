import SwiftUI

import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionStore {
    @ObservationIgnored
    private let storageKey = "subscriptions.v1"

    var subscriptions: [Subscription] {
        didSet { persist(); refreshReminders() }
    }
    var currency: String {
        didSet { UserDefaults.standard.set(currency, forKey: "currency"); refreshReminders() }
    }
    var remindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled")
            if remindersEnabled { NotificationManager.requestAuthorization() }
            refreshReminders()
        }
    }
    /// Ile godzin przed płatnością ma przyjść powiadomienie (0 = w dniu płatności).
    var reminderHours: Int {
        didSet { UserDefaults.standard.set(reminderHours, forKey: "reminderHours"); refreshReminders() }
    }
    var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: "soundsEnabled") }
    }
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: "userName") }
    }
    var userEmail: String {
        didSet { UserDefaults.standard.set(userEmail, forKey: "userEmail") }
    }

    init() {
        let d = UserDefaults.standard
        currency = d.string(forKey: "currency") ?? "PLN"
        remindersEnabled = d.object(forKey: "remindersEnabled") as? Bool ?? true
        soundsEnabled = d.object(forKey: "soundsEnabled") as? Bool ?? true
        language = d.string(forKey: "language") ?? "Polski"
        userName = d.string(forKey: "userName") ?? "Jan Kowalski"
        userEmail = d.string(forKey: "userEmail") ?? "jan.kowalski@email.com"

        // Godziny przed płatnością (z migracją starego ustawienia w dniach).
        let hours: Int
        if let saved = d.object(forKey: "reminderHours") as? Int {
            hours = saved
        } else if let oldDays = d.object(forKey: "reminderDays") as? Int {
            hours = oldDays * 24
            d.set(hours, forKey: "reminderHours")
            d.removeObject(forKey: "reminderDays")
        } else {
            hours = 24
        }
        reminderHours = hours

        if let data = d.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Subscription].self, from: data) {
            subscriptions = decoded
        } else {
            subscriptions = Self.sampleData()
        }

        // didSet nie wywołuje się w init, więc planujemy powiadomienia przy starcie.
        refreshReminders()
    }

    // MARK: - Dane przykładowe (zgodne z makietą)

    private static func sampleData() -> [Subscription] {
        func make(_ name: String, _ price: Double, _ date: Date) -> Subscription {
            let s = Service.catalog.first { $0.name == name }
            return Subscription(name: name, price: price, period: .month, firstPayment: date,
                                category: s?.category ?? .other,
                                symbol: s?.symbol ?? "creditcard.fill",
                                colorHex: s?.colorHex ?? 0x5E6AD2)
        }
        return [
            make("Netflix", 22.99, AppCal.date(2026, 10, 23)),
            make("Spotify", 11.99, AppCal.date(2026, 10, 24)),
            make("YouTube", 13.99, AppCal.date(2026, 10, 26)),
            make("Apple TV+", 9.99, AppCal.date(2026, 10, 28)),
            make("iCloud+", 2.99, AppCal.date(2026, 11, 1)),
            make("Adobe", 52.99, AppCal.date(2026, 11, 3))
        ]
    }

    // MARK: - Utrwalanie

    private func persist() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func refreshReminders() {
        NotificationManager.reschedule(subscriptions,
                                       enabled: remindersEnabled,
                                       hoursBefore: reminderHours,
                                       money: { [currency] in Self.format($0, currency: currency) })
    }

    // MARK: - Operacje

    func add(_ sub: Subscription) {
        subscriptions.append(sub)
        SoundManager.success(enabled: soundsEnabled)
    }

    func delete(_ sub: Subscription) {
        subscriptions.removeAll { $0.id == sub.id }
    }

    // MARK: - Obliczenia

    var monthlyTotal: Double { subscriptions.reduce(0) { $0 + $1.monthlyCost } }
    var yearlyTotal: Double { subscriptions.reduce(0) { $0 + $1.yearlyCost } }

    /// Subskrypcje posortowane po dacie najbliższej płatności.
    var upcoming: [(sub: Subscription, date: Date)] {
        subscriptions
            .compactMap { s in s.nextPayment().map { (s, $0) } }
            .sorted { $0.1 < $1.1 }
    }

    var nextPayment: (sub: Subscription, date: Date)? { upcoming.first }

    func payments(inMonthOf month: Date) -> [(sub: Subscription, date: Date)] {
        guard let interval = AppCal.cal.dateInterval(of: .month, for: month) else { return [] }
        return subscriptions
            .flatMap { s in s.occurrences(from: interval.start, to: interval.end).map { (s, $0) } }
            .sorted { $0.1 < $1.1 }
    }

    /// Sumy płatności z ostatnich `count` miesięcy (łącznie z bieżącym).
    func monthTotals(last count: Int) -> [MonthTotal] {
        let cal = AppCal.cal
        let thisMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        return (0..<count).reversed().compactMap { offset in
            guard let m = cal.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            let sum = payments(inMonthOf: m).reduce(0) { $0 + $1.sub.price }
            return MonthTotal(date: m, amount: sum)
        }
    }

    // MARK: - Formatowanie

    nonisolated static func format(_ v: Double, currency: String) -> String {
        let whole = abs(v.truncatingRemainder(dividingBy: 1)) < 0.005
        return v.formatted(
            .currency(code: currency)
                .locale(AppCal.locale)
                .precision(.fractionLength(whole ? 0 : 2))
        )
    }

    func money(_ v: Double) -> String { Self.format(v, currency: currency) }

    func dayText(_ date: Date) -> String {
        let cal = AppCal.cal
        if cal.isDateInToday(date) { return "Dziś" }
        if cal.isDateInTomorrow(date) { return "Jutro" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(AppCal.locale))
    }
}

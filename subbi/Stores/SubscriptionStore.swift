import SwiftUI

import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionStore {
    @ObservationIgnored
    private let storageKey = "subscriptions.v1"

    var subscriptions: [Subscription] {
        didSet {
            persist()
            refreshReminders()
            if !isReplacing { onSubscriptionsChange?() }
        }
    }

    /// Wywoływane po każdej zmianie listy przez użytkownika (synchronizacja z serwerem – `AuthStore`).
    @ObservationIgnored var onSubscriptionsChange: (() -> Void)?
    @ObservationIgnored private var isReplacing = false
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
    /// Ile godzin przed płatnością ma przyjść powiadomienie.
    var reminderHours: Int {
        didSet { UserDefaults.standard.set(reminderHours, forKey: "reminderHours"); refreshReminders() }
    }
    var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: "soundsEnabled") }
    }
    /// Język interfejsu – zmiana od razu przełącza tłumaczenia i formaty dat/kwot.
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            AppLanguage.activate(language)
            refreshReminders() // treść powiadomień w nowym języku
        }
    }

    init() {
        let d = UserDefaults.standard
        // Język najpierw – od niego zależą tłumaczenia i AppCal.
        let lang = AppLanguage.saved(in: d)
        AppLanguage.activate(lang)
        language = lang
        currency = d.string(forKey: "currency") ?? "PLN"
        remindersEnabled = d.object(forKey: "remindersEnabled") as? Bool ?? true
        soundsEnabled = d.object(forKey: "soundsEnabled") as? Bool ?? true

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
        // Opcja „w dniu płatności” (0 h) została usunięta – zastępuje ją najbliższa: godzina przed.
        reminderHours = max(1, hours)
        if hours < 1 { d.set(1, forKey: "reminderHours") }

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
            let due = AppCal.cal.date(bySettingHour: NotificationManager.dueHour, minute: 0, second: 0, of: date) ?? date
            return Subscription(name: name, price: price, period: .month, firstPayment: due,
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

    /// Zapisuje zmiany w istniejącej subskrypcji (rozpoznawanej po `id`).
    func update(_ sub: Subscription) {
        guard let i = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        var sub = sub
        // Edycja może przesunąć datę dezaktywacji, ale nie zmienia stanu: aktywna zostaje aktywna, nieaktywna – nieaktywna.
        sub.deactivatedAt = subscriptions[i].deactivatedAt.map { sub.deactivatedAt ?? $0 }
        // Bez zmian – nie ma czego wysyłać na serwer.
        if subscriptions[i] != sub { subscriptions[i] = sub }
        SoundManager.success(enabled: soundsEnabled)
    }

    /// Dezaktywuje subskrypcję (nieodwracalnie): płatności od tej chwili znikają, wcześniejsze zostają.
    func deactivate(_ sub: Subscription) {
        guard let i = subscriptions.firstIndex(where: { $0.id == sub.id }), subscriptions[i].isActive else { return }
        subscriptions[i].deactivatedAt = .now
    }

    func delete(_ sub: Subscription) {
        subscriptions.removeAll { $0.id == sub.id }
    }

    /// Podmienia listę danymi z serwera (lub czyści przy wylogowaniu) bez ponownego wysyłania jej na serwer.
    func replaceSubscriptions(_ list: [Subscription]) {
        isReplacing = true
        defer { isReplacing = false }
        subscriptions = list
    }

    // MARK: - Obliczenia

    var activeSubscriptions: [Subscription] { subscriptions.filter(\.isActive) }

    /// Nieaktywne, od ostatnio dezaktywowanej.
    var inactiveSubscriptions: [Subscription] {
        subscriptions
            .filter { !$0.isActive }
            .sorted { ($0.deactivatedAt ?? .distantPast) > ($1.deactivatedAt ?? .distantPast) }
    }

    var monthlyTotal: Double { activeSubscriptions.reduce(0) { $0 + $1.monthlyCost } }
    var yearlyTotal: Double { activeSubscriptions.reduce(0) { $0 + $1.yearlyCost } }

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

    /// - Parameter reference: kwota, według której dobierana jest liczba miejsc po przecinku
    ///   (domyślnie `v`) – np. końcowa wartość licznika, żeby format nie zmieniał się w trakcie animacji.
    nonisolated static func format(_ v: Double, currency: String, like reference: Double? = nil) -> String {
        let whole = abs((reference ?? v).truncatingRemainder(dividingBy: 1)) < 0.005
        return v.formatted(
            .currency(code: currency)
                .locale(AppCal.locale)
                .precision(.fractionLength(whole ? 0 : 2))
        )
    }

    func money(_ v: Double) -> String { Self.format(v, currency: currency) }

    func dayText(_ date: Date) -> String {
        let cal = AppCal.cal
        if cal.isDateInToday(date) { return String(localized: "Dziś", bundle: .appLanguage) }
        if cal.isDateInTomorrow(date) { return String(localized: "Jutro", bundle: .appLanguage) }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(AppCal.locale))
    }
}

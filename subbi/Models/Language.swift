import Foundation

/// Język interfejsu wybierany w ustawieniach (niezależnie od języka systemu).
///
/// Teksty są w `Localizable.xcstrings` (język źródłowy: polski, tłumaczenie: angielski).
/// - `Text("…")` i inne widoki SwiftUI tłumaczą się według `\.locale`, które ustawia `subbiApp`.
/// - Teksty budowane w kodzie: `String(localized: "…", bundle: .appLanguage)`.
///   Samo `String(localized:)` brałoby język systemu, a nie wybrany w aplikacji.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case pl, en

    var id: String { rawValue }

    /// Nazwa języka w nim samym – celowo bez tłumaczenia.
    var nativeName: String { self == .pl ? "Polski" : "English" }

    /// Locale do formatowania dat i kwot oraz tłumaczeń SwiftUI.
    var locale: Locale { Locale(identifier: self == .pl ? "pl_PL" : "en_US") }

    /// Tabela tłumaczeń języka (`<kod>.lproj` w pakiecie aplikacji).
    var bundle: Bundle { Self.bundles[self] ?? .main }

    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues: allCases.compactMap { lang in
        Bundle.main.path(forResource: lang.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)).map { (lang, $0) }
    })

    /// Bieżący język aplikacji. Zmieniany tylko przez `activate(_:)` (z głównego wątku).
    nonisolated(unsafe) private(set) static var current: AppLanguage = .pl

    static func activate(_ language: AppLanguage) {
        current = language
    }

    /// Zapisane ustawienie (z migracją dawnych wartości „Polski” / „English”).
    static func saved(in defaults: UserDefaults = .standard) -> AppLanguage {
        switch defaults.string(forKey: "language") {
        case "en", "English": return .en
        default: return .pl
        }
    }

    /// Tłumaczy komunikat z serwera (subbi-backend odpowiada po polsku).
    /// Nieznane komunikaty zostają bez zmian.
    static func translateServerMessage(_ message: String) -> String {
        current.bundle.localizedString(forKey: message, value: message, table: nil)
    }
}

extension Bundle {
    /// Tabela tłumaczeń języka wybranego w aplikacji – do `String(localized:bundle:)`.
    nonisolated static var appLanguage: Bundle { AppLanguage.current.bundle }
}

// MARK: - Odmiana liczebników

nonisolated enum Plural {
    /// Polska forma liczebnika: 1 → one, 2–4 (bez 12–14) → few, reszta → many.
    static func polish(_ n: Int, one: String, few: String, many: String) -> String {
        if n == 1 { return one }
        let n10 = n % 10, n100 = n % 100
        return (2...4).contains(n10) && !(12...14).contains(n100) ? few : many
    }

    /// „1 godzinę”, „3 godziny”, „5 godzin” / „1 hour”, „3 hours”.
    static func hours(_ h: Int) -> String {
        switch AppLanguage.current {
        case .pl: return "\(h) " + polish(h, one: "godzinę", few: "godziny", many: "godzin")
        case .en: return h == 1 ? "1 hour" : "\(h) hours"
        }
    }

    /// „1 dzień”, „3 dni” / „1 day”, „3 days”.
    static func days(_ d: Int) -> String {
        switch AppLanguage.current {
        case .pl: return d == 1 ? "1 dzień" : "\(d) dni"
        case .en: return d == 1 ? "1 day" : "\(d) days"
        }
    }
}

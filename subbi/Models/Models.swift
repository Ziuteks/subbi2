import SwiftUI

nonisolated enum AppCal {
    private static let calendars: [AppLanguage: Calendar] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { lang in
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // poniedziałek
        c.locale = lang.locale
        return (lang, c)
    })

    /// Kalendarz i locale zależą od języka wybranego w aplikacji.
    static var cal: Calendar { calendars[AppLanguage.current]! }
    static var locale: Locale { AppLanguage.current.locale }

    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d)) ?? .now
    }
}

enum BillingPeriod: String, Codable, CaseIterable, Identifiable {
    case month, year
    var id: String { rawValue }
    var title: String { self == .month ? String(localized: "Miesiąc", bundle: .appLanguage) : String(localized: "Rok", bundle: .appLanguage) }
    var adverb: String { self == .month ? String(localized: "miesięcznie", bundle: .appLanguage) : String(localized: "rocznie", bundle: .appLanguage) }
    var component: Calendar.Component { self == .month ? .month : .year }
}

enum SubCategory: String, Codable, CaseIterable, Identifiable {
    case entertainment, tools, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .entertainment: return String(localized: "Rozrywka", bundle: .appLanguage)
        case .tools: return String(localized: "Narzędzia", bundle: .appLanguage)
        case .other: return String(localized: "Inne", bundle: .appLanguage)
        }
    }
    var color: Color {
        switch self {
        case .entertainment: return Color(hex: 0xFF3B30)
        case .tools: return Color(hex: 0x0A84FF)
        case .other: return Color(hex: 0xFF9F0A)
        }
    }
}

struct Subscription: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var price: Double
    var period: BillingPeriod
    var firstPayment: Date
    var category: SubCategory
    var symbol: String
    var colorHex: UInt32

    var color: Color { Color(hex: colorHex) }
    var monthlyCost: Double { period == .month ? price : price / 12 }
    var yearlyCost: Double { period == .month ? price * 12 : price }

    /// Daty płatności w przedziale [start, end).
    func occurrences(from start: Date, to end: Date) -> [Date] {
        var result: [Date] = []
        var n = 0
        while let d = AppCal.cal.date(byAdding: period.component, value: n, to: firstPayment), d < end {
            if d >= start { result.append(d) }
            n += 1
            if n > 5000 { break }
        }
        return result
    }

    /// Ikona do wyświetlenia: logo marki, jeśli nazwa pasuje do serwisu z katalogu
    /// (także dla subskrypcji zapisanych wcześniej z ikoną SF Symbol), w przeciwnym razie zapisana ikona.
    var iconSymbol: String { Service.matching(name)?.symbol ?? symbol }

    func nextPayment(after ref: Date = .now) -> Date? {
        let start = AppCal.cal.startOfDay(for: ref)
        guard let end = AppCal.cal.date(byAdding: .day, value: 400, to: start) else { return nil }
        return occurrences(from: start, to: end).first
    }
}

struct Service: Identifiable {
    var id: String { name }
    let name: String
    let symbol: String
    let colorHex: UInt32
    let category: SubCategory
    let price: Double

    var color: Color { Color(hex: colorHex) }

    /// `symbol` z prefiksem `brand:` to logo z Assets.xcassets/Brands (zob. tools/brand-icons).
    static let catalog: [Service] = [
        Service(name: "Netflix", symbol: "brand:netflix", colorHex: 0xE50914, category: .entertainment, price: 22.99),
        Service(name: "Spotify", symbol: "brand:spotify", colorHex: 0x1DB954, category: .entertainment, price: 11.99),
        Service(name: "YouTube", symbol: "brand:youtube", colorHex: 0xFF0000, category: .entertainment, price: 13.99),
        Service(name: "Adobe", symbol: "brand:adobe", colorHex: 0xFA0F00, category: .tools, price: 52.99),
        Service(name: "iCloud+", symbol: "brand:icloud", colorHex: 0x3B82F6, category: .tools, price: 2.99),
        Service(name: "Apple TV+", symbol: "brand:appletv", colorHex: 0x2C2C2E, category: .entertainment, price: 9.99),
        Service(name: "HBO Max", symbol: "brand:hbomax", colorHex: 0x6C2BD9, category: .entertainment, price: 29.99),
        Service(name: "Prime Video", symbol: "brand:primevideo", colorHex: 0x00A8E1, category: .entertainment, price: 10.99),
        Service(name: "Disney+", symbol: "brand:disneyplus", colorHex: 0x113CCF, category: .entertainment, price: 28.99),
        Service(name: "Microsoft 365", symbol: "brand:microsoft365", colorHex: 0xD83B01, category: .tools, price: 29.99),
        Service(name: "Dropbox", symbol: "brand:dropbox", colorHex: 0x0061FF, category: .tools, price: 49.99),
        Service(name: "Notion", symbol: "brand:notion", colorHex: 0x3A3A3C, category: .tools, price: 39.99),
        Service(name: "Claude", symbol: "brand:claude", colorHex: 0xD97757, category: .tools, price: 20.00),
        Service(name: "ChatGPT", symbol: "brand:chatgpt", colorHex: 0x10A37F, category: .tools, price: 20.00),
        Service(name: "Gemini", symbol: "brand:gemini", colorHex: 0x4285F4, category: .tools, price: 19.99)
    ]

    /// Serwis z katalogu o tej nazwie (bez względu na wielkość liter i spacje na brzegach).
    static func matching(_ name: String) -> Service? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.first { $0.name.lowercased() == key }
    }
}

struct CategoryAmount: Identifiable {
    let category: SubCategory
    let amount: Double
    var id: SubCategory { category }
}

struct MonthTotal: Identifiable {
    let date: Date
    let amount: Double
    var id: Date { date }
}

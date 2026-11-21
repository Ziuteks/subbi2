import SwiftUI

enum Theme {
    static let bg = Color(red: 0.12, green: 0.16, blue: 0.27)
    static let card = Color(red: 0.18, green: 0.23, blue: 0.36)
    static let accent = Color(red: 0.53, green: 1.0, blue: 0.78)
    static let alert = Color(red: 1.0, green: 0.23, blue: 0.27)
    static let muted = Color.white.opacity(0.55)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }

    func screenBackground() -> some View {
        self.background(Theme.bg.ignoresSafeArea())
    }
}

/// Kwadratowa ikona usługi: logo marki (`symbol` = `brand:<nazwa>`, kafelek z Assets.xcassets/Brands)
/// albo kolor + symbol SF dla pozostałych.
struct ServiceIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.25, style: .continuous) }

    var body: some View {
        if let brand = symbol.brandAssetName {
            Image(brand)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(shape)
                // Delikatna obwódka, żeby czarne kafelki (Netflix, Apple TV…) nie zlewały się z ciemnym tłem.
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .accessibilityHidden(true)
        } else {
            shape
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

private extension String {
    /// `brand:netflix` → `brand-netflix` (nazwa zasobu), inaczej nil.
    var brandAssetName: String? {
        hasPrefix("brand:") ? "brand-" + dropFirst("brand:".count) : nil
    }
}

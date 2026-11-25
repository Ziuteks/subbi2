import SwiftUI

enum AppTab: Hashable {
    case home, calendar, stats, settings
}

struct ContentView: View {
    var store: SubscriptionStore
    var auth: AuthStore
    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            HomeView(store: store)
                .tabItem { Label("Główna", systemImage: "house.fill") }
                .tag(AppTab.home)

            CalendarView(store: store)
                .tabItem { Label("Kalendarz", systemImage: "calendar") }
                .tag(AppTab.calendar)

            StatsView(store: store, isActive: selection == .stats)
                .tabItem { Label("Statystyki", systemImage: "chart.bar.fill") }
                .tag(AppTab.stats)

            SettingsView(store: store, auth: auth)
                .tabItem { Label("Ustawienia", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

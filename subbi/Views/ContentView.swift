import SwiftUI

enum AppTab: Hashable {
    case home, calendar, stats, add, settings
}

struct ContentView: View {
    var store: SubscriptionStore
    var auth: AuthStore
    @State private var selection: AppTab = .home
    @State private var showAdd = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView(store: store)
                .tabItem { Label("Główna", systemImage: "house.fill") }
                .tag(AppTab.home)

            CalendarView(store: store)
                .tabItem { Label("Kalendarz", systemImage: "calendar") }
                .tag(AppTab.calendar)

            StatsView(store: store)
                .tabItem { Label("Statystyki", systemImage: "chart.bar.fill") }
                .tag(AppTab.stats)

            Color.clear
                .tabItem { Label("Dodaj", systemImage: "plus") }
                .tag(AppTab.add)

            SettingsView(store: store, auth: auth)
                .tabItem { Label("Ustawienia", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        // Zakładka „Dodaj" otwiera formularz wysuwany od dołu i nie zmienia ekranu.
        .onChange(of: selection) { old, new in
            if new == .add {
                selection = old
                showAdd = true
            }
        }
        .sheet(isPresented: $showAdd) {
            AddSubscriptionView(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

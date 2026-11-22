import SwiftUI

@main
struct subbiApp: App {
    @State private var store: SubscriptionStore
    @State private var auth: AuthStore
    /// Wybrana zakładka – trzymana tutaj, żeby przetrwała przebudowę widoków po zmianie języka.
    @State private var tab: AppTab = .home
    /// Animacja startowa – tylko przy uruchomieniu aplikacji (nie przy powrocie z tła ani zmianie języka).
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = SubscriptionStore()
        _store = State(initialValue: store)
        _auth = State(initialValue: AuthStore(store: store))

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.card)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if auth.isLoggedIn {
                        ContentView(store: store, auth: auth, selection: $tab)
                            .onAppear {
                                if store.remindersEnabled { NotificationManager.requestAuthorization() }
                                store.refreshReminders()
                            }
                    } else {
                        LoginView(auth: auth)
                    }
                }
                // Zmiana języka: nowe locale (daty, kwoty, tłumaczenia Text) i przebudowa całego interfejsu,
                // bo teksty z String(localized:) liczone są w trakcie budowania widoków.
                .environment(\.locale, store.language.locale)
                .id(store.language)
                .environment(store)
                .environment(auth)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .animation(.default, value: auth.isLoggedIn)
                // Przy starcie i każdym powrocie do aplikacji: dosyłamy zmiany i pobieramy stan z serwera.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { Task { await auth.refresh() } }
                }

                if showSplash {
                    SplashView(onFinish: finishSplash)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
    }

    private func finishSplash() {
        guard showSplash else { return }
        withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
    }
}
//

import SwiftUI

@main
struct subbiApp: App {
    @State private var store: SubscriptionStore
    @State private var auth: AuthStore
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
            Group {
                if auth.isLoggedIn {
                    ContentView(store: store, auth: auth)
                        .onAppear {
                            if store.remindersEnabled { NotificationManager.requestAuthorization() }
                            store.refreshReminders()
                        }
                } else {
                    LoginView(auth: auth)
                }
            }
            .environment(store)
            .environment(auth)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .animation(.default, value: auth.isLoggedIn)
            // Przy starcie i każdym powrocie do aplikacji: dosyłamy zmiany i pobieramy stan z serwera.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { Task { await auth.refresh() } }
            }
        }
    }
}
//

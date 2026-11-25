import Foundation
import Observation

/// Sesja użytkownika i synchronizacja subskrypcji z subbi-backend.
///
/// Zasady synchronizacji:
/// - po każdej lokalnej zmianie cała lista jest wysyłana na serwer (z krótkim opóźnieniem),
/// - przy logowaniu/rejestracji: jeśli konto na serwerze ma subskrypcje – pobieramy je,
///   jeśli jest puste – wysyłamy listę z telefonu,
/// - przy powrocie do aplikacji: najpierw wysyłamy niezsynchronizowane zmiany, potem pobieramy stan z serwera.
@MainActor
@Observable
final class AuthStore {
    enum SyncState: Equatable {
        case idle, syncing
        case failed(String)
    }

    /// Adres backendu wbudowany w aplikację: Build Settings → `API_BASE_URL` (Debug / Release),
    /// przekazywany przez klucz `SubbiAPIBaseURL` w subbi-Info.plist.
    static let defaultServerURL: String = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "SubbiAPIBaseURL") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty || value.contains("$(") ? "http://localhost:3000" : value
    }()

    private(set) var user: AuthUser? {
        didSet { saveUser() }
    }
    private(set) var token: String? {
        didSet { Keychain.set(token, for: tokenKey) }
    }
    /// Adres serwera – zawsze z konfiguracji buildu (zob. `defaultServerURL`).
    let serverURL = AuthStore.defaultServerURL
    private(set) var syncState: SyncState = .idle
    /// Komunikat dla ekranu logowania (np. po wygaśnięciu sesji).
    var notice: String?

    var isLoggedIn: Bool { token != nil }

    @ObservationIgnored private let store: SubscriptionStore
    @ObservationIgnored private let tokenKey = "auth.token"
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var isPushing = false
    @ObservationIgnored private var isRefreshing = false
    /// Czy lokalne zmiany czekają na wysłanie (przetrwa restart aplikacji).
    @ObservationIgnored private var dirty: Bool {
        didSet { UserDefaults.standard.set(dirty, forKey: "sync.dirty") }
    }

    init(store: SubscriptionStore) {
        self.store = store
        let d = UserDefaults.standard
        d.removeObject(forKey: "serverURL") // dawny ręcznie wpisany adres – teraz adres pochodzi tylko z buildu
        dirty = d.bool(forKey: "sync.dirty")
        token = Keychain.get(tokenKey)
        if let data = d.data(forKey: "auth.user") {
            user = try? JSONDecoder().decode(AuthUser.self, from: data)
        }
        store.onSubscriptionsChange = { [weak self] in self?.schedulePush() }
    }

    private var api: APIClient { APIClient(baseURL: serverURL, token: token) }

    // MARK: - Logowanie

    func login(email: String, password: String) async throws {
        let session = try await APIClient(baseURL: serverURL).login(email: email, password: password)
        try await start(session)
    }

    func register(name: String, email: String, password: String) async throws {
        let session = try await APIClient(baseURL: serverURL).register(name: name, email: email, password: password)
        try await start(session)
        // Nowe konto zaczyna z językiem systemu (później można go zmienić w ustawieniach).
        store.language = .system
    }

    private func start(_ session: AuthSession) async throws {
        let client = APIClient(baseURL: serverURL, token: session.token)
        let remote = try await client.fetchSubscriptions()
        if remote.isEmpty {
            try await client.saveSubscriptions(store.subscriptions)
        } else {
            store.replaceSubscriptions(remote)
        }
        dirty = false
        notice = nil
        syncState = .idle
        user = session.user
        token = session.token
    }

    /// Wylogowuje i czyści dane z urządzenia (najpierw próbuje wysłać niezsynchronizowane zmiany).
    func logout() async {
        await pushIfNeeded()
        clearSession()
    }

    private func clearSession() {
        debounceTask?.cancel()
        token = nil
        user = nil
        dirty = false
        syncState = .idle
        store.replaceSubscriptions([])
    }

    // MARK: - Konto

    func updateProfile(name: String, email: String) async throws {
        do {
            user = try await api.updateProfile(name: name, email: email)
        } catch {
            handleUnauthorized(error)
            throw error
        }
    }

    func changePassword(current: String, new: String) async throws {
        do {
            let session = try await api.changePassword(current: current, new: new)
            token = session.token
            user = session.user
        } catch {
            handleUnauthorized(error)
            throw error
        }
    }

    // MARK: - Synchronizacja

    private func schedulePush() {
        guard isLoggedIn else { return }
        dirty = true
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.pushIfNeeded()
        }
    }

    /// Wysyła listę, dopóki są niezsynchronizowane zmiany (zmiany w trakcie wysyłki trafią w kolejnej rundzie).
    func pushIfNeeded() async {
        guard isLoggedIn, dirty, !isPushing else { return }
        isPushing = true
        defer { isPushing = false }
        syncState = .syncing
        while dirty {
            dirty = false
            do {
                try await api.saveSubscriptions(store.subscriptions)
            } catch {
                dirty = true
                fail(error)
                return
            }
        }
        syncState = .idle
    }

    /// Wywoływane przy starcie i powrocie do aplikacji.
    func refresh() async {
        guard isLoggedIn, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if dirty {
            await pushIfNeeded()
            if dirty { return } // nie nadpisujemy lokalnych zmian, których nie udało się wysłać
        }
        syncState = .syncing
        do {
            async let me = api.me()
            async let remote = api.fetchSubscriptions()
            let (newUser, list) = try await (me, remote)
            user = newUser
            // Użytkownik mógł coś zmienić w trakcie pobierania – wtedy wygrywa wersja lokalna.
            if !dirty { store.replaceSubscriptions(list) }
            syncState = .idle
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        if error is CancellationError { syncState = .idle; return }
        if handleUnauthorized(error) { return }
        syncState = .failed(error.localizedDescription)
    }

    /// Przy 401 (token wygasł lub hasło zmieniono na innym urządzeniu) kończy sesję.
    @discardableResult
    private func handleUnauthorized(_ error: Error) -> Bool {
        guard (error as? APIError)?.isUnauthorized == true, isLoggedIn else { return false }
        clearSession()
        notice = String(localized: "Sesja wygasła. Zaloguj się ponownie.", bundle: .appLanguage)
        return true
    }

    private func saveUser() {
        let d = UserDefaults.standard
        if let user, let data = try? JSONEncoder().encode(user) {
            d.set(data, forKey: "auth.user")
        } else {
            d.removeObject(forKey: "auth.user")
        }
    }
}

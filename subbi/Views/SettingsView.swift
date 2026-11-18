import SwiftUI

struct SettingsView: View {
    @Bindable var store: SubscriptionStore
    @State private var showLogoutDialog = false
    @State private var loggedOut = false

    private let currencies = ["PLN", "EUR", "USD", "GBP"]
    private let languages = ["Polski", "English"]

    /// Dostępne opcje przypomnienia (w godzinach przed płatnością).
    private let baseReminderOptions = [0, 1, 3, 6, 12, 24, 48, 72, 168]

    /// Opcje + bieżąca wartość, gdyby nie było jej na liście
    /// (np. po migracji starego ustawienia z dni), żeby Picker zawsze miał zaznaczenie.
    private var reminderOptions: [Int] {
        var options = baseReminderOptions
        if !options.contains(store.reminderHours) {
            options.append(store.reminderHours)
        }
        return options.sorted()
    }

    private var initials: String {
        store.userName.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    /// Etykieta opcji z polską odmianą (godzinę / godziny / godzin, dzień / dni).
    private func reminderLabel(_ h: Int) -> String {
        if h == 0 { return "W dniu płatności" }
        if h % 24 == 0 {
            let d = h / 24
            return d == 1 ? "1 dzień przed" : "\(d) dni przed"
        }
        if h == 1 { return "1 godzinę przed" }
        let n10 = h % 10, n100 = h % 100
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "\(h) godziny przed" }
        return "\(h) godzin przed"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Konto") {
                    NavigationLink {
                        ProfileView(store: store)
                    } label: {
                        HStack(spacing: 12) {
                            Text(initials.isEmpty ? "?" : initials)
                                .font(.headline)
                                .frame(width: 44, height: 44)
                                .background(Theme.accent.opacity(0.25), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.userName).font(.headline)
                                Text(store.userEmail).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Subskrypcje i płatności") {
                    Picker("Domyślna waluta", selection: $store.currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Powiadomienia") {
                    Toggle("Przypomnienia o płatnościach", isOn: $store.remindersEnabled)
                        .listRowBackground(Theme.card)
                    if store.remindersEnabled {
                        Picker("Przypomnij", selection: $store.reminderHours) {
                            ForEach(reminderOptions, id: \.self) { hours in
                                Text(reminderLabel(hours)).tag(hours)
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                    Toggle("Dźwięki", isOn: $store.soundsEnabled)
                        .listRowBackground(Theme.card)
                }

                Section("Bezpieczeństwo i język") {
                    NavigationLink("Zmień hasło") { PasswordView() }
                        .listRowBackground(Theme.card)
                    Picker("Język aplikacji", selection: $store.language) {
                        ForEach(languages, id: \.self) { Text($0).tag($0) }
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutDialog = true
                    } label: {
                        Text("Wyloguj się").frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(Theme.alert, lineWidth: 1)
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Ustawienia")
            .confirmationDialog("Czy na pewno chcesz się wylogować?",
                                isPresented: $showLogoutDialog, titleVisibility: .visible) {
                Button("Wyloguj się", role: .destructive) { loggedOut = true }
                Button("Anuluj", role: .cancel) {}
            }
            .alert("Wylogowano", isPresented: $loggedOut) {
                Button("OK") {}
            } message: {
                Text("To wersja demonstracyjna bez serwera kont – dane pozostają na urządzeniu.")
            }
        }
    }
}

struct ProfileView: View {
    @Bindable var store: SubscriptionStore

    var body: some View {
        Form {
            Section("Dane użytkownika") {
                TextField("Imię i nazwisko", text: $store.userName)
                TextField("Adres e-mail", text: $store.userEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Konto")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var repeatNew = ""
    @State private var done = false

    private var valid: Bool { new.count >= 8 && new == repeatNew && !current.isEmpty }

    var body: some View {
        Form {
            Section {
                SecureField("Obecne hasło", text: $current)
                SecureField("Nowe hasło (min. 8 znaków)", text: $new)
                SecureField("Powtórz nowe hasło", text: $repeatNew)
            }
            .listRowBackground(Theme.card)

            Section {
                Button("Zapisz") { done = true }
                    .disabled(!valid)
                    .frame(maxWidth: .infinity)
            } footer: {
                if !new.isEmpty && new != repeatNew {
                    Text("Hasła nie są takie same.").foregroundStyle(Theme.alert)
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Zmień hasło")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Hasło zmienione", isPresented: $done) {
            Button("OK") { dismiss() }
        } message: {
            Text("Wersja demonstracyjna – hasło nie jest wysyłane na serwer.")
        }
    }
}

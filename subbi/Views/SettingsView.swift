import SwiftUI

struct SettingsView: View {
    @Bindable var store: SubscriptionStore
    var auth: AuthStore
    @State private var showLogoutDialog = false

    private let currencies = ["PLN", "EUR", "USD", "GBP"]

    /// Dostępne opcje przypomnienia (w godzinach przed płatnością).
    private let baseReminderOptions = [1, 3, 6, 12, 24, 48, 72, 168]

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
        (auth.user?.name ?? "").split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    /// Etykieta opcji z odmianą liczebnika („3 godziny przed”, „2 dni przed” / „3 hours before”).
    private func reminderLabel(_ h: Int) -> String {
        let amount = h % 24 == 0 ? Plural.days(h / 24) : Plural.hours(h)
        return String(localized: "\(amount) przed", bundle: .appLanguage)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Konto") {
                    NavigationLink {
                        ProfileView(auth: auth)
                    } label: {
                        HStack(spacing: 12) {
                            Text(initials.isEmpty ? "?" : initials)
                                .font(.headline)
                                .frame(width: 44, height: 44)
                                .background(Theme.accent.opacity(0.25), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(auth.user?.name ?? String(localized: "Moje konto", bundle: .appLanguage)).font(.headline)
                                Text(auth.user?.email ?? "").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    syncRow
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
                    NavigationLink("Zmień hasło") { PasswordView(auth: auth) }
                        .listRowBackground(Theme.card)
                    Picker("Język aplikacji", selection: $store.language) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.nativeName).tag($0) }
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutDialog = true
                    } label: {
                        Text("Wyloguj się")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    // Przyciemnienie jak w „Dodaj subskrypcję”; przycisk zostaje przyciemniony, dopóki okienko jest otwarte.
                    .buttonStyle(DimmingButtonStyle(isHeld: showLogoutDialog))
                    // Okienko podpięte do samego przycisku, żeby wyświetlało się przy nim (a nie u góry ekranu).
                    // Własny popover, bo systemowy confirmationDialog nie pozwala pewnie ustawić koloru przycisków.
                    .popover(isPresented: $showLogoutDialog) {
                        logoutConfirmation
                            .presentationCompactAdaptation(.popover)
                            .presentationBackground(Theme.card)
                    }
                    // Bez marginesów wiersza, żeby przycisk miał szerokość i wysokość zwykłej rubryki.
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Ustawienia")
        }
    }

    /// Okno potwierdzenia wylogowania (dotknięcie poza nim działa jak „Anuluj").
    private var logoutConfirmation: some View {
        VStack(spacing: 12) {
            Text("Czy na pewno chcesz się wylogować?")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Subskrypcje zostaną usunięte z tego urządzenia – pozostaną na Twoim koncie.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            Button {
                showLogoutDialog = false
                Task { await auth.logout() }
            } label: {
                Text("Wyloguj się")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Button {
                showLogoutDialog = false
            } label: {
                Text("Anuluj")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 300)
    }

    /// Stan synchronizacji z serwerem; dotknięcie wymusza synchronizację.
    private var syncRow: some View {
        Button {
            Task { await auth.refresh() }
        } label: {
            HStack(spacing: 12) {
                switch auth.syncState {
                case .idle:
                    Image(systemName: "checkmark.icloud.fill").foregroundStyle(Theme.accent)
                    Text("Zsynchronizowano")
                case .syncing:
                    ProgressView()
                    Text("Synchronizacja…")
                case .failed(let message):
                    Image(systemName: "exclamationmark.icloud.fill").foregroundStyle(Theme.alert)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Błąd synchronizacji – dotknij, aby ponowić")
                        Text(message).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .disabled(auth.syncState == .syncing)
    }
}

struct ProfileView: View {
    var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var error: String?
    @State private var isSaving = false

    private var changed: Bool { name != auth.user?.name || email != auth.user?.email }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && email.contains("@")
    }

    var body: some View {
        Form {
            Section("Dane użytkownika") {
                TextField("Imię i nazwisko", text: $name)
                    .textContentType(.name)
                TextField("Adres e-mail", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    save()
                } label: {
                    if isSaving { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Zapisz").frame(maxWidth: .infinity) }
                }
                .disabled(!changed || !valid || isSaving)
            } footer: {
                if let error { Text(error).foregroundStyle(Theme.alert) }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Konto")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = auth.user?.name ?? ""
            email = auth.user?.email ?? ""
        }
    }

    private func save() {
        error = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await auth.updateProfile(name: name.trimmingCharacters(in: .whitespaces),
                                             email: email.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct PasswordView: View {
    var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var repeatNew = ""
    @State private var done = false
    @State private var error: String?
    @State private var isSaving = false

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
                Button {
                    save()
                } label: {
                    if isSaving { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Zapisz").frame(maxWidth: .infinity) }
                }
                .disabled(!valid || isSaving)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(Theme.alert)
                } else if !new.isEmpty && new != repeatNew {
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
            Text("Na innych urządzeniach trzeba będzie zalogować się ponownie.")
        }
    }

    private func save() {
        error = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await auth.changePassword(current: current, new: new)
                done = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

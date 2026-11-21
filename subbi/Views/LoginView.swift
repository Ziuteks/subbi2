import SwiftUI

struct LoginView: View {
    var auth: AuthStore

    private enum Mode: String, CaseIterable, Identifiable {
        case login, register
        var id: String { rawValue }
        var title: String { self == .login ? "Logowanie" : "Rejestracja" }
    }

    private enum Field: Hashable { case name, email, password, repeatPassword }

    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var repeatPassword = ""
    @State private var error: String?
    @State private var isLoading = false
    @FocusState private var focus: Field?

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var valid: Bool {
        switch mode {
        case .login:
            return !trimmedEmail.isEmpty && !password.isEmpty
        case .register:
            return !trimmedName.isEmpty && trimmedEmail.contains("@")
                && password.count >= 8 && password == repeatPassword
        }
    }

    private var hint: String? {
        guard mode == .register else { return nil }
        if !password.isEmpty && password.count < 8 { return "Hasło musi mieć co najmniej 8 znaków." }
        if !repeatPassword.isEmpty && password != repeatPassword { return "Hasła nie są takie same." }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                Picker("Tryb", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { error = nil }

                VStack(spacing: 12) {
                    if mode == .register {
                        field("Imię i nazwisko", text: $name, id: .name)
                            .textContentType(.name)
                    }
                    field("Adres e-mail", text: $email, id: .email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    field(mode == .register ? "Hasło (min. 8 znaków)" : "Hasło",
                          text: $password, id: .password, secure: true)
                        .textContentType(mode == .register ? .newPassword : .password)
                    if mode == .register {
                        field("Powtórz hasło", text: $repeatPassword, id: .repeatPassword, secure: true)
                            .textContentType(.newPassword)
                    }
                }

                if let message = error ?? hint ?? auth.notice {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.alert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    ZStack {
                        Text(mode == .login ? "Zaloguj się" : "Utwórz konto").opacity(isLoading ? 0 : 1)
                        if isLoading { ProgressView().tint(Theme.bg) }
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent.opacity(valid ? 1 : 0.4),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!valid || isLoading)
            }
            .padding(24)
            .animation(.default, value: mode)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .onSubmit(next)
    }

    private var header: some View {
        VStack(spacing: 10) {
            ServiceIcon(symbol: "creditcard.fill", color: Theme.accent.opacity(0.35), size: 72)
            Text("Subbi").font(.largeTitle.bold())
            Text("Zaloguj się, aby Twoje subskrypcje były bezpieczne na każdym urządzeniu.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, id: Field, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
            }
        }
        .focused($focus, equals: id)
        .submitLabel(.next)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Klawisz „Dalej” przechodzi do kolejnego pola, w ostatnim – wysyła formularz.
    private func next() {
        let order: [Field] = mode == .register ? [.name, .email, .password, .repeatPassword] : [.email, .password]
        if let current = focus, let i = order.firstIndex(of: current), i + 1 < order.count {
            focus = order[i + 1]
        } else {
            submit()
        }
    }

    private func submit() {
        guard valid, !isLoading else { return }
        focus = nil
        error = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                switch mode {
                case .login:
                    try await auth.login(email: trimmedEmail, password: password)
                case .register:
                    try await auth.register(name: trimmedName, email: trimmedEmail, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

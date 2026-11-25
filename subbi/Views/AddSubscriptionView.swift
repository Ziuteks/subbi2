import SwiftUI

/// Formularz subskrypcji: dodawanie nowej albo – gdy podano `editing` – edycja istniejącej.
struct AddSubscriptionView: View {
    var store: SubscriptionStore
    private let editing: Subscription?
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var selected: Service?
    @State private var name = ""
    @State private var priceText = ""
    @State private var period: BillingPeriod = .month
    @State private var category: SubCategory = .entertainment
    @State private var firstPayment = Date.now
    /// Godzina płatności (liczy się tylko godzina i minuta, data jest pomijana).
    @State private var paymentTime = AppCal.cal.date(bySettingHour: NotificationManager.dueHour,
                                                     minute: 0, second: 0, of: .now) ?? .now
    /// Moment dezaktywacji – używany tylko przy edycji nieaktywnej subskrypcji.
    @State private var deactivatedAt = Date.now
    @State private var showDeleteDialog = false

    init(store: SubscriptionStore, editing: Subscription? = nil) {
        self.store = store
        self.editing = editing
        guard let editing else { return }
        _name = State(initialValue: editing.name)
        _priceText = State(initialValue: Self.priceText(editing.price))
        _period = State(initialValue: editing.period)
        _category = State(initialValue: editing.category)
        _firstPayment = State(initialValue: editing.firstPayment)
        _paymentTime = State(initialValue: editing.firstPayment)
        _deactivatedAt = State(initialValue: editing.deactivatedAt ?? .now)
    }

    private var isInactive: Bool { editing?.isActive == false }

    private var screenTitle: LocalizedStringKey { editing == nil ? "Dodaj subskrypcję" : "Edytuj subskrypcję" }

    private var parsedPrice: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (parsedPrice ?? 0) > 0
    }

    private var filtered: [Service] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? Service.catalog
            : Service.catalog.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    /// Data pierwszej płatności połączona z wybraną godziną.
    private var firstPaymentDateTime: Date {
        let cal = AppCal.cal
        let t = cal.dateComponents([.hour, .minute], from: paymentTime)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0,
                        of: cal.startOfDay(for: firstPayment)) ?? firstPayment
    }

    private var draft: Subscription {
        // Przy edycji ikona podąża za nazwą z katalogu, a dla innych nazw zostaje dotychczasowa.
        let match = editing == nil ? (selected?.name == name ? selected : nil) : Service.matching(name)
        return Subscription(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            price: parsedPrice ?? 0,
            period: period,
            firstPayment: firstPaymentDateTime,
            category: category,
            symbol: match?.symbol ?? editing?.symbol ?? "creditcard.fill",
            colorHex: match?.colorHex ?? editing?.colorHex ?? 0x5E6AD2,
            deactivatedAt: isInactive ? min(deactivatedAt, .now) : nil // nigdy w przyszłości
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if editing == nil {
                        searchField
                        Text("POPULARNE SERWISY")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                        servicesRow
                    } else {
                        ServiceIcon(symbol: draft.iconSymbol, color: draft.color, size: 72)
                            .frame(maxWidth: .infinity)
                    }
                    formCard
                    infoText
                    Button(action: save) {
                        Label(editing == nil ? "Dodaj" : "Zapisz",
                              systemImage: editing == nil ? "plus" : "checkmark")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent.opacity(canSave ? 1 : 0.4),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(!canSave)
                    if let editing { deleteButton(editing) }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zapisz", action: save).disabled(!canSave)
                }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Szukaj usługi…", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var servicesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(filtered) { service in
                    Button { choose(service) } label: {
                        VStack(spacing: 6) {
                            ServiceIcon(symbol: service.symbol, color: service.color, size: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Theme.accent, lineWidth: selected?.id == service.id ? 2.5 : 0)
                                )
                            Text(service.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.white)
                        }
                        .frame(width: 62)
                    }
                    .buttonStyle(.plain)
                }
                if filtered.isEmpty {
                    Text("Brak wyników – wpisz nazwę ręcznie poniżej.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nazwa")
                TextField("np. Netflix", text: $name)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 12)
            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text("Cena")
                TextField("0,00", text: $priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.muted)
                Text(store.currency).font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 12)
            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text("Okres")
                Spacer()
                Picker("Okres", selection: $period) {
                    ForEach(BillingPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text("Kategoria")
                Spacer()
                Picker("Kategoria", selection: $category) {
                    ForEach(SubCategory.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.vertical, 4)
            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text("Data pierwszej płatności")
                Spacer()
                Text(firstPayment.formatted(.dateTime.month(.abbreviated).day().year().locale(AppCal.locale)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
            .padding(.top, 12)

            DatePicker("Data", selection: $firstPayment, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, AppCal.locale)
                .frame(maxWidth: .infinity)
            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text("Godzina płatności")
                Spacer()
                DatePicker("Godzina", selection: $paymentTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.locale, AppCal.locale)
            }
            .padding(.vertical, 8)

            if isInactive { deactivationRows }
        }
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var deactivationRows: some View {
        Divider().overlay(Color.white.opacity(0.1))
        HStack {
            Text("Data dezaktywacji")
            Spacer()
            DatePicker("Data dezaktywacji", selection: $deactivatedAt, in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, AppCal.locale)
        }
        .padding(.vertical, 8)
        Divider().overlay(Color.white.opacity(0.1))
        HStack {
            Text("Godzina dezaktywacji")
            Spacer()
            DatePicker("Godzina dezaktywacji", selection: $deactivatedAt, in: ...Date.now,
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, AppCal.locale)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var infoText: some View {
        if canSave, let next = draft.nextPayment() {
            let unit = period == .month ? String(localized: "miesiąc", bundle: .appLanguage) : String(localized: "rok", bundle: .appLanguage)
            Text("Odnowi się co \(unit) od daty pierwszej płatności. Twoja następna płatność: \(next.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().locale(AppCal.locale))).")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private func deleteButton(_ sub: Subscription) -> some View {
        Button {
            showDeleteDialog = true
        } label: {
            Label("Usuń subskrypcję", systemImage: "trash")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.alert, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(DimmingButtonStyle(isHeld: showDeleteDialog))
        .confirmationDialog("Czy na pewno chcesz usunąć tę subskrypcję?",
                            isPresented: $showDeleteDialog, titleVisibility: .visible) {
            Button("Usuń", role: .destructive) {
                store.delete(sub)
                dismiss()
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Tej operacji nie można cofnąć.")
        }
    }

    /// Cena do pola tekstowego, z separatorem jak w wybranym języku (parsedPrice przyjmuje oba).
    private static func priceText(_ value: Double) -> String {
        let price = String(format: "%.2f", value)
        return AppLanguage.current == .pl ? price.replacingOccurrences(of: ".", with: ",") : price
    }

    private func choose(_ service: Service) {
        selected = service
        name = service.name
        category = service.category
        priceText = Self.priceText(service.price)
        SoundManager.tap(enabled: store.soundsEnabled)
    }

    private func save() {
        guard canSave else { return }
        if editing == nil { store.add(draft) } else { store.update(draft) }
        dismiss()
    }
}

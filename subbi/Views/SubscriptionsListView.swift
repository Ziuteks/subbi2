import SwiftUI
import Charts

/// „Moje subskrypcje" – lista aktywnych usług z podsumowaniem i mini wykresem trendu.
struct SubscriptionsListView: View {
    var store: SubscriptionStore
    /// Subskrypcja otwarta do edycji.
    @State private var editing: Subscription?
    /// Subskrypcja, o której dezaktywację pytamy (po przytrzymaniu wiersza).
    /// Zostaje ustawiona po zamknięciu okienka, żeby nazwa w tytule nie znikła w trakcie jego chowania.
    @State private var deactivating: Subscription?
    @State private var showDeactivate = false
    /// Wiersz przyciemniony w trakcie naciskania.
    @State private var pressedID: UUID?

    private var totals: [MonthTotal] { store.monthTotals(last: 6) }

    private var change: Double {
        guard totals.count >= 2 else { return 0 }
        return totals[totals.count - 1].amount - totals[totals.count - 2].amount
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ForEach(store.upcoming, id: \.sub.id) { item in
                    // Gesty zamiast Button: po przytrzymaniu Button wykonałby jeszcze zwykłe dotknięcie.
                    row(item.sub, store.dayText(item.date))
                        .opacity(pressedID == item.sub.id ? 0.6 : 1)
                        .onTapGesture { editing = item.sub }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            askToDeactivate(item.sub)
                        } onPressingChanged: { pressing in
                            pressedID = pressing ? item.sub.id : nil
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { editing = item.sub }
                        .accessibilityAction(named: Text("Dezaktywuj")) { askToDeactivate(item.sub) }
                        .listRowBackground(Theme.card)
                        .swipeActions { deleteAction(item.sub) }
                }
            } header: {
                HStack {
                    Text("Aktywne subskrypcje")
                    Spacer()
                    Text("\(store.activeSubscriptions.count)")
                }
            } footer: {
                Label("Posortowane według daty płatności", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }

            if !store.inactiveSubscriptions.isEmpty {
                Section {
                    ForEach(store.inactiveSubscriptions) { sub in
                        Button { editing = sub } label: {
                            row(sub, inactiveText(sub))
                                .grayscale(1)
                                .opacity(0.5)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                        .swipeActions { deleteAction(sub) }
                    }
                } header: {
                    HStack {
                        Text("Nieaktywne subskrypcje")
                        Spacer()
                        Text("\(store.inactiveSubscriptions.count)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Moje subskrypcje")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { sub in
            AddSubscriptionView(store: store, editing: sub)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(Text("Dezaktywować „\(deactivating?.name ?? "")”?"), isPresented: $showDeactivate,
               presenting: deactivating) { sub in
            Button("Dezaktywuj", role: .destructive) {
                withAnimation { store.deactivate(sub) }
            }
            Button("Anuluj", role: .cancel) {}
        } message: { _ in
            Text("Kolejne płatności nie będą naliczane, a dotychczasowe zostaną na wykresie. Dezaktywowanej subskrypcji nie można ponownie aktywować.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Miesięczne wydatki")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            HStack(alignment: .center) {
                Text(store.money(store.monthlyTotal))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer()
                Chart(totals) { item in
                    LineMark(x: .value("Miesiąc", item.date), y: .value("Kwota", item.amount))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(width: 90, height: 40)
            }
            changeLabel
        }
        .cardStyle()
    }

    @ViewBuilder
    private var changeLabel: some View {
        if abs(change) < 0.005 {
            Text("Bez zmian w porównaniu z poprzednim miesiącem")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        } else if change < 0 {
            Text("▼ \(store.money(-change)) mniej niż w poprzednim miesiącu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        } else {
            Text("▲ \(store.money(change)) więcej niż w poprzednim miesiącu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.alert)
        }
    }

    private func askToDeactivate(_ sub: Subscription) {
        deactivating = sub
        showDeactivate = true
    }

    private func deleteAction(_ sub: Subscription) -> some View {
        Button(role: .destructive) {
            withAnimation { store.delete(sub) }
        } label: {
            Label("Usuń", systemImage: "trash")
        }
    }

    private func inactiveText(_ sub: Subscription) -> String {
        let date = (sub.deactivatedAt ?? .now).formatted(.dateTime.day().month(.abbreviated).year().locale(AppCal.locale))
        return String(localized: "Nieaktywna od \(date)", bundle: .appLanguage)
    }

    private func row(_ sub: Subscription, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            ServiceIcon(symbol: sub.iconSymbol, color: sub.color, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.money(sub.price)).font(.subheadline.weight(.semibold))
                Text(sub.period.adverb)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle()) // cały wiersz reaguje na dotknięcie, także puste miejsce
    }
}

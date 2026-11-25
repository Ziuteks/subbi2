import SwiftUI

struct HomeView: View {
    var store: SubscriptionStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatCard(title: "Twoje miesięczne wydatki", value: store.money(store.monthlyTotal))
                    StatCard(title: "Twoje roczne wydatki", value: store.money(store.yearlyTotal))
                    nextPaymentCard
                    allSubscriptionsLink
                    addButton
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Ekran główny")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showAdd) {
            AddSubscriptionView(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var nextPaymentCard: some View {
        HStack(spacing: 12) {
            if let next = store.nextPayment {
                ServiceIcon(symbol: next.sub.iconSymbol, color: next.sub.color, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Następna płatność")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                    Text(next.sub.name)
                        .font(.headline)
                    Text("\(store.dayText(next.date)) · \(store.money(next.sub.price))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text("Brak nadchodzących płatności")
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .cardStyle()
    }

    private var allSubscriptionsLink: some View {
        NavigationLink {
            SubscriptionsListView(store: store)
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text("Moje subskrypcje")
                    .font(.headline)
                Spacer()
                Text("\(store.activeSubscriptions.count)")
                    .foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(.white)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            Label("Dodaj subskrypcję", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(DimmingButtonStyle())
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .cardStyle()
    }
}

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: HistoryStore
    @State private var query = ""
    @State private var confirmClear = false

    private var filtered: [Dictation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.items }
        return store.items.filter {
            $0.text.localizedCaseInsensitiveContains(q) || ($0.appName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        var items: [Dictation]
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        var result: [DayGroup] = []
        for item in filtered {
            let day = calendar.startOfDay(for: item.date)
            if let last = result.last, last.day == day {
                result[result.count - 1].items.append(item)
            } else {
                result.append(DayGroup(day: day, items: [item]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                PageHeader(title: "Historique", subtitle: "Toutes tes dictées, gardées uniquement sur ce Mac.")
                Spacer()
                if !store.items.isEmpty {
                    Button("Tout effacer") { confirmClear = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.muted)
                TextField("Rechercher un mot, une appli…", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.navy)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.paper)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            )

            if groups.isEmpty {
                Card {
                    Text(store.items.isEmpty
                         ? "Aucune dictée pour l'instant. Maintiens le raccourci dans n'importe quelle app et parle."
                         : "Aucun résultat pour « \(query) ».")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Formatters.day(group.day))
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.muted)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Card(padding: 18) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().overlay(Theme.line) }
                                    DictationRow(item: item, showDay: false) {
                                        store.delete(item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Effacer tout l'historique ?", isPresented: $confirmClear) {
            Button("Tout effacer", role: .destructive) { store.clear() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les dictées seront supprimées de ce Mac. Les statistiques repartiront de zéro.")
        }
    }
}

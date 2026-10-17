import SwiftUI
import Charts

struct DashboardView: View {
    @Binding var section: AppSection
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: HistoryStore
    @EnvironmentObject private var transcriber: Transcriber
    @EnvironmentObject private var permissions: PermissionsManager

    private let columns = [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18),
                           GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]

    init(section: Binding<AppSection>) {
        _section = section
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            WelcomeBanner()

            if !controller.isReady || !settings.hasAPIKey {
                SetupCard(section: $section)
            }

            LazyVGrid(columns: columns, spacing: 18) {
                StatTile(symbol: "text.alignleft", label: "Mots dictés",
                         value: store.totalWords.formatted(),
                         detail: store.count <= 1 ? "\(store.count) dictée" : "\(store.count) dictées")
                StatTile(symbol: "sun.max", label: "Aujourd'hui",
                         value: store.wordsToday.formatted(),
                         detail: todayDetail)
                StatTile(symbol: "speedometer", label: "Vitesse",
                         value: store.averageWPM.formatted(),
                         detail: "mots par minute en moyenne")
                StatTile(symbol: "hourglass", label: "Temps gagné",
                         value: Formatters.duration(store.timeSaved),
                         detail: "face à \(Int(HistoryStore.typingWordsPerMinute)) mots/min au clavier")
            }

            HStack(alignment: .top, spacing: 18) {
                DailyChartCard()
                    .frame(maxWidth: .infinity)
                    .layoutPriority(2)
                AppSharesCard()
                    .frame(width: 320)
            }

            RecentCard(section: $section)
        }
    }

    private var todayDetail: String {
        let today = store.wordsToday
        let yesterday = store.wordsYesterday
        if yesterday == 0 {
            return today > 0 ? "rien hier : bon début" : "pas encore de dictée aujourd'hui"
        }
        let change = Int((Double(today - yesterday) / Double(yesterday) * 100).rounded())
        return "\(change >= 0 ? "+" : "")\(change) % par rapport à hier"
    }
}

// MARK: - Bandeau d'accueil

private struct WelcomeBanner: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(settings.firstName.isEmpty ? "Salut !" : "Salut \(settings.firstName)")
                    .font(Theme.font(32, .heavy))
                    .tracking(-1.2)
                    .foregroundStyle(Theme.paper)
                HStack(spacing: 12) {
                    Text(settings.hotkey.label)
                        .font(Theme.font(12, .bold))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.mustard))
                    Text("Maintiens, parle, relâche : Plume écrit à ta place.")
                        .font(Theme.font(14, .medium))
                        .foregroundStyle(Theme.paper.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
            WaveMark(
                heights: [0.25, 0.5, 0.35, 0.8, 0.55, 1.0, 0.65, 0.9, 0.45, 0.7, 0.3, 0.55, 0.2],
                barWidth: 5,
                spacing: 6
            )
            .frame(width: 150, height: 70)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.navy)
        )
    }
}

// MARK: - Mise en route

private struct SetupCard: View {
    @Binding var section: AppSection
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var transcriber: Transcriber
    @EnvironmentObject private var permissions: PermissionsManager

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mise en route")
                    .font(Theme.font(17, .bold))
                    .foregroundStyle(Theme.navy)

                SetupRow(
                    done: permissions.microphone == .granted,
                    title: "Micro",
                    detail: "Plume n'écoute que pendant que tu maintiens le raccourci.",
                    action: permissions.microphone == .granted ? nil : ("Autoriser", { permissions.requestMicrophone() })
                )
                SetupRow(
                    done: permissions.accessibility,
                    title: "Accessibilité",
                    detail: "Pour détecter le raccourci et coller le texte là où tu écris. Active Plume dans la liste qui s'ouvre.",
                    action: permissions.accessibility ? nil : ("Ouvrir les réglages", { permissions.requestAccessibility() })
                )
                SetupRow(
                    done: transcriber.status == .ready,
                    title: "Modèle de transcription",
                    detail: modelDetail,
                    action: modelAction
                )
                SetupRow(
                    done: settings.hasAPIKey,
                    title: "Clé Claude (conseillé)",
                    detail: "Pour remettre ton texte au propre : ponctuation, « euh » retirés, corrections.",
                    action: settings.hasAPIKey ? nil : ("Ajouter", { section = .settings })
                )
            }
        }
    }

    private var modelDetail: String {
        switch transcriber.status {
        case .downloading(let fraction):
            return "Téléchargement : \(Int(fraction * 100)) % (environ 630 Mo, une seule fois)."
        case .loading:
            return "Préparation sur ton Mac. La première fois, ça peut prendre quelques minutes."
        case .failed(let message):
            return "Échec : \(message)"
        case .ready:
            return "Prêt, tout se passe sur ton Mac : ta voix ne quitte jamais l'ordinateur."
        case .idle:
            return "Démarrage…"
        }
    }

    private var modelAction: (String, () -> Void)? {
        if case .failed = transcriber.status {
            return ("Réessayer", { controller.retryModel() })
        }
        return nil
    }
}

private struct SetupRow: View {
    let done: Bool
    let title: String
    let detail: String
    let action: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Theme.mustard : Theme.canvas)
                    .overlay(Circle().strokeBorder(done ? Color.clear : Theme.line, lineWidth: 1))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.navy)
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.navy)
                Text(detail)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(PillButtonStyle())
            }
        }
    }
}

// MARK: - Tuiles de chiffres

private struct StatTile: View {
    let symbol: String
    let label: String
    let value: String
    let detail: String

    var body: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(Theme.mustardTint)
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.navy)
                }
                .frame(width: 38, height: 38)
                .padding(.bottom, 16)

                Text(label)
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.muted)
                Text(value)
                    .font(Theme.font(32, .heavy))
                    .tracking(-1)
                    .foregroundStyle(Theme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.vertical, 2)
                Text(detail)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Graphique des 14 derniers jours

private struct DailyChartCard: View {
    @EnvironmentObject private var store: HistoryStore
    @State private var hoveredDay: Date?

    var body: some View {
        let data = store.dailyTotals(days: 14)
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mots dictés par jour")
                            .font(Theme.font(17, .bold))
                            .foregroundStyle(Theme.navy)
                        Text("14 derniers jours")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if store.streak > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(Theme.gold)
                            Text(store.streak == 1 ? "1 jour d'affilée" : "\(store.streak) jours d'affilée")
                                .font(Theme.font(12, .semibold))
                                .foregroundStyle(Theme.navy)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.mustardTint))
                    }
                }

                Chart(data) { item in
                    BarMark(
                        x: .value("Jour", item.day, unit: .day),
                        y: .value("Mots", item.words),
                        width: .ratio(0.62)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(Calendar.current.isDateInToday(item.day) ? Theme.mustard : Theme.navy)
                    .opacity(hoveredDay == nil || isSameDay(hoveredDay, item.day) ? 1 : 0.45)
                    .annotation(position: .top, spacing: 4) {
                        if isSameDay(hoveredDay, item.day) || (hoveredDay == nil && Calendar.current.isDateInToday(item.day) && item.words > 0) {
                            Text("\(item.words.formatted()) mots")
                                .font(Theme.font(11, .semibold))
                                .foregroundStyle(Theme.navy)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Theme.line)
                        AxisValueLabel()
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let x = location.x - geo[plotFrame].origin.x
                                    if let date: Date = proxy.value(atX: x) {
                                        hoveredDay = Calendar.current.startOfDay(for: date)
                                    }
                                case .ended:
                                    hoveredDay = nil
                                }
                            }
                    }
                }
                .frame(height: 230)
                .overlay {
                    if store.totalWords == 0 {
                        Text("Ta première dictée apparaîtra ici.")
                            .font(Theme.font(13, .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private func isSameDay(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }
}

// MARK: - Où je dicte

private struct AppSharesCard: View {
    @EnvironmentObject private var store: HistoryStore

    var body: some View {
        let shares = store.appShares(top: 6)
        Card {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Où je dicte")
                        .font(Theme.font(17, .bold))
                        .foregroundStyle(Theme.navy)
                    Text("Part de mes mots par appli")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                }
                if shares.isEmpty {
                    Text("Rien pour l'instant.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(shares) { share in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(share.name)
                                    .font(Theme.font(13, .semibold))
                                    .foregroundStyle(Theme.navy)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int((share.share * 100).rounded())) %")
                                    .font(Theme.font(13, .bold))
                                    .foregroundStyle(Theme.navy)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.canvas)
                                    Capsule()
                                        .fill(Theme.navy)
                                        .frame(width: max(6, geo.size.width * share.share))
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Dernières dictées

private struct RecentCard: View {
    @Binding var section: AppSection
    @EnvironmentObject private var store: HistoryStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mes dernières dictées")
                        .font(Theme.font(17, .bold))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    if store.count > 5 {
                        Button("Tout voir") { section = .history }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
                .padding(.bottom, 10)

                if store.items.isEmpty {
                    Text("Place ton curseur dans n'importe quelle app, maintiens le raccourci et parle.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(store.items.prefix(5).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.line) }
                        DictationRow(item: item, showDay: false)
                    }
                }
            }
        }
    }
}

/// Une dictée, avec bouton pour la recopier.
struct DictationRow: View {
    let item: Dictation
    var showDay: Bool
    var onDelete: (() -> Void)?
    @State private var hovering = false
    @State private var copied = false

    init(item: Dictation, showDay: Bool, onDelete: (() -> Void)? = nil) {
        self.item = item
        self.showDay = showDay
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(Formatters.time(item.date))
                .font(Theme.font(14, .bold))
                .foregroundStyle(Theme.navy)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let app = item.appName { Tag(text: app) }
                    Text(item.words <= 1 ? "\(item.words) mot" : "\(item.words) mots")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                    if !item.cleaned {
                        Text("brut")
                            .font(Theme.font(11, .medium))
                            .foregroundStyle(Theme.soft)
                    }
                }
                Text(item.text)
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.navy)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button {
                    Clipboard.copy(item.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(copied ? Theme.gold : Theme.muted)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.canvas))
                }
                .buttonStyle(.plain)
                .help("Copier")
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.canvas))
                    }
                    .buttonStyle(.plain)
                    .help("Supprimer de l'historique")
                }
            }
            .opacity(hovering || copied ? 1 : 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum Formatters {
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date).capitalized(with: Locale(identifier: "fr_FR"))
    }

    /// 45 s, 12 min, 1 h 05
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d", minutes / 60, minutes % 60)
    }
}

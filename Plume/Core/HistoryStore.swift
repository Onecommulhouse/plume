import Foundation

struct Dictation: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var rawText: String
    var words: Int
    /// Durée de parole, en secondes.
    var duration: TimeInterval
    var appName: String?
    var appBundleID: String?
    var cleaned: Bool
}

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Plume", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension String {
    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }
}

/// Historique local des dictées (fichier JSON dans Application Support) et statistiques du tableau de bord.
@MainActor
final class HistoryStore: ObservableObject {
    /// Les plus récentes en premier.
    @Published private(set) var items: [Dictation] = []

    /// Vitesse de frappe de référence pour calculer le temps gagné.
    static let typingWordsPerMinute = 40.0
    private let maxItems = 10_000
    private let fileURL = AppPaths.support.appendingPathComponent("history.json")

    init() {
        load()
    }

    func add(_ dictation: Dictation) {
        items.insert(dictation, at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }
        save()
    }

    func delete(_ dictation: Dictation) {
        items.removeAll { $0.id == dictation.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([Dictation].self, from: data)) ?? []
    }

    private func save() {
        let snapshot = items
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Statistiques

    private var calendar: Calendar { Calendar.current }

    var totalWords: Int { items.reduce(0) { $0 + $1.words } }
    var count: Int { items.count }

    func words(on day: Date) -> Int {
        items.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.words }
    }

    var wordsToday: Int { words(on: Date()) }

    var wordsYesterday: Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return 0 }
        return words(on: yesterday)
    }

    var dictationsToday: Int {
        items.filter { calendar.isDateInToday($0.date) }.count
    }

    /// Mots par minute de parole, en moyenne.
    var averageWPM: Int {
        let minutes = items.reduce(0) { $0 + $1.duration } / 60
        guard minutes > 0.05 else { return 0 }
        return Int((Double(totalWords) / minutes).rounded())
    }

    /// Temps gagné par rapport à la frappe au clavier, en secondes.
    var timeSaved: TimeInterval {
        let typing = Double(totalWords) / Self.typingWordsPerMinute * 60
        let speaking = items.reduce(0) { $0 + $1.duration }
        return max(0, typing - speaking)
    }

    struct DayTotal: Identifiable {
        let day: Date
        let words: Int
        var id: Date { day }
    }

    func dailyTotals(days: Int = 14) -> [DayTotal] {
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayTotal(day: day, words: words(on: day))
        }
    }

    /// Nombre de jours consécutifs avec au moins une dictée (aujourd'hui ou hier inclus).
    var streak: Int {
        var day = calendar.startOfDay(for: Date())
        if words(on: day) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while words(on: day) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    struct AppShare: Identifiable {
        let name: String
        let share: Double
        var id: String { name }
    }

    func appShares(top: Int = 5) -> [AppShare] {
        let total = Double(totalWords)
        guard total > 0 else { return [] }
        var byApp: [String: Int] = [:]
        for item in items {
            byApp[item.appName ?? "Autre", default: 0] += item.words
        }
        return byApp
            .sorted { $0.value > $1.value }
            .prefix(top)
            .map { AppShare(name: $0.key, share: Double($0.value) / total) }
    }
}

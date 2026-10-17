import Foundation
import AppKit
import ServiceManagement

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case rightOption
    case rightCommand
    case fn

    var id: String { rawValue }

    /// Nom affiché dans l'interface.
    var label: String {
        switch self {
        case .rightOption: return "Option droite"
        case .rightCommand: return "Commande droite"
        case .fn: return "Fn (🌐)"
        }
    }

    /// Code de touche macOS (kVK_RightOption, kVK_RightCommand, kVK_Function).
    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .fn: return 63
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightCommand: return .command
        case .fn: return .function
        }
    }
}

enum LanguageChoice: String, CaseIterable, Identifiable {
    case fr
    case en
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fr: return "Français"
        case .en: return "Anglais"
        case .auto: return "Détection automatique"
        }
    }

    /// Code passé à Whisper (nil = détection automatique).
    var whisperCode: String? {
        switch self {
        case .fr: return "fr"
        case .en: return "en"
        case .auto: return nil
        }
    }
}

/// Constantes de l'app (hors acteur principal, utilisables partout).
enum PlumeConfig {
    /// Modèle Whisper (version « turbo » compressée, recommandée par Argmax pour la précision multilingue).
    static let whisperModel = "large-v3-v20240930_626MB"
    static let claudeModel = "claude-haiku-5-5"
    static let defaultVocabulary = ["ONE COM", "Matego", "Plume", "Mulhouse"]
}

/// Réglages de Plume, enregistrés dans les préférences macOS.
@MainActor
final class AppSettings: ObservableObject {

    private let defaults = UserDefaults.standard

    @Published var firstName: String { didSet { defaults.set(firstName, forKey: "firstName") } }
    @Published var hotkey: HotkeyChoice { didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var language: LanguageChoice { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var cleanupEnabled: Bool { didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var keepInClipboard: Bool { didSet { defaults.set(keepInClipboard, forKey: "keepInClipboard") } }
    @Published var muteWhileDictating: Bool { didSet { defaults.set(muteWhileDictating, forKey: "muteWhileDictating") } }
    @Published var vocabulary: [String] { didSet { defaults.set(vocabulary, forKey: "vocabulary") } }
    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var launchAtLogin: Bool

    init() {
        let d = UserDefaults.standard
        let fullName = NSFullUserName()
        let guessedFirstName = fullName.split(separator: " ").first.map(String.init) ?? ""
        firstName = d.string(forKey: "firstName") ?? guessedFirstName
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightOption
        language = LanguageChoice(rawValue: d.string(forKey: "language") ?? "") ?? .fr
        cleanupEnabled = d.object(forKey: "cleanupEnabled") as? Bool ?? true
        soundsEnabled = d.object(forKey: "soundsEnabled") as? Bool ?? true
        keepInClipboard = d.object(forKey: "keepInClipboard") as? Bool ?? false
        muteWhileDictating = d.object(forKey: "muteWhileDictating") as? Bool ?? true
        vocabulary = d.stringArray(forKey: "vocabulary") ?? PlumeConfig.defaultVocabulary
        hasAPIKey = !(Keychain.read(Keychain.anthropicAccount) ?? "").isEmpty
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var apiKey: String? { Keychain.read(Keychain.anthropicAccount) }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(Keychain.anthropicAccount)
        } else {
            Keychain.save(trimmed, account: Keychain.anthropicAccount)
        }
        hasAPIKey = !trimmed.isEmpty
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Plume: lancement au démarrage impossible : \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func addWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !vocabulary.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        vocabulary.append(trimmed)
    }

    func removeWord(_ word: String) {
        vocabulary.removeAll { $0 == word }
    }
}

/// Stockage de la clé API dans le trousseau macOS.
enum Keychain {
    static let service = "com.onecom.plume"
    static let anthropicAccount = "anthropic-api-key"

    static func save(_ value: String, account: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

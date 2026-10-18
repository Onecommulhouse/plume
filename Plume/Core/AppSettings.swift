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

/// Ton de la mise au propre, réglable app par app.
enum WritingStyle: String, CaseIterable, Identifiable {
    case auto
    case professional
    case casual
    case asIs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatique"
        case .professional: return "Soigné"
        case .casual: return "Détendu"
        case .asIs: return "Tel quel"
        }
    }

    var hint: String {
        switch self {
        case .auto: return "Claude choisit selon la fenêtre ouverte."
        case .professional: return "Phrases complètes, mise en forme d'e-mail."
        case .casual: return "Naturel et direct, comme un message."
        case .asIs: return "Juste corrigé, ton inchangé."
        }
    }
}

/// Langues proposées pour la traduction directe.
enum TranslationLanguage: String, CaseIterable, Identifiable {
    case en, es, de, it, pt, nl, ar, tr

    var id: String { rawValue }

    /// Nom affiché dans les réglages.
    var label: String {
        switch self {
        case .en: return "Anglais"
        case .es: return "Espagnol"
        case .de: return "Allemand"
        case .it: return "Italien"
        case .pt: return "Portugais"
        case .nl: return "Néerlandais"
        case .ar: return "Arabe"
        case .tr: return "Turc"
        }
    }

    /// Nom donné à Claude dans la consigne.
    var promptName: String {
        switch self {
        case .en: return "anglais"
        case .es: return "espagnol"
        case .de: return "allemand"
        case .it: return "italien"
        case .pt: return "portugais"
        case .nl: return "néerlandais"
        case .ar: return "arabe"
        case .tr: return "turc"
        }
    }

    /// Pastille affichée pendant la dictée.
    var badge: String { rawValue.uppercased() }
}

/// Constantes de l'app (hors acteur principal, utilisables partout).
enum PlumeConfig {
    /// Modèle Whisper (version « turbo » compressée, recommandée par Argmax pour la précision multilingue).
    static let whisperModel = "large-v3-v20240930_626MB"
    static let claudeModel = "claude-haiku-5-5"
    static let defaultVocabulary = ["ONE COM", "Matego", "Plume", "Mulhouse"]

    /// Ton par défaut des apps courantes (modifiable dans les réglages). Les autres apps sont en « Automatique ».
    static let defaultStyles: [String: WritingStyle] = [
        // E-mail et documents : soigné
        "com.apple.mail": .professional,
        "com.microsoft.Outlook": .professional,
        "com.readdle.smartemail-Mac": .professional,
        "com.superhuman.electron": .professional,
        "com.microsoft.Word": .professional,
        "com.apple.iWork.Pages": .professional,
        // Messageries : détendu
        "net.whatsapp.WhatsApp": .casual,
        "desktop.WhatsApp": .casual,
        "com.apple.MobileSMS": .casual,
        "com.tinyspeck.slackmacgap": .casual,
        "ru.keepcoder.Telegram": .casual,
        "com.hnc.Discord": .casual,
        "com.facebook.archon": .casual,
        "org.whispersystems.signal-desktop": .casual,
    ]
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
    @Published var showLiveText: Bool { didSet { defaults.set(showLiveText, forKey: "showLiveText") } }
    @Published var handsFreeEnabled: Bool { didSet { defaults.set(handsFreeEnabled, forKey: "handsFreeEnabled") } }
    @Published var adaptTone: Bool { didSet { defaults.set(adaptTone, forKey: "adaptTone") } }
    @Published var useWindowContext: Bool { didSet { defaults.set(useWindowContext, forKey: "useWindowContext") } }
    @Published var translationTarget: TranslationLanguage { didSet { defaults.set(translationTarget.rawValue, forKey: "translationTarget") } }
    /// Ton choisi à la main, app par app (identifiant de l'app → WritingStyle).
    @Published var appStyles: [String: String] { didSet { defaults.set(appStyles, forKey: "appStyles") } }
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
        showLiveText = d.object(forKey: "showLiveText") as? Bool ?? true
        handsFreeEnabled = d.object(forKey: "handsFreeEnabled") as? Bool ?? true
        adaptTone = d.object(forKey: "adaptTone") as? Bool ?? true
        useWindowContext = d.object(forKey: "useWindowContext") as? Bool ?? true
        translationTarget = TranslationLanguage(rawValue: d.string(forKey: "translationTarget") ?? "") ?? .en
        appStyles = d.dictionary(forKey: "appStyles") as? [String: String] ?? [:]
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

    /// Ton à appliquer pour une app : choix manuel, sinon préréglage, sinon automatique.
    func style(forBundleID bundleID: String?) -> WritingStyle {
        guard let bundleID, !bundleID.isEmpty else { return .auto }
        if let raw = appStyles[bundleID], let chosen = WritingStyle(rawValue: raw) { return chosen }
        return PlumeConfig.defaultStyles[bundleID] ?? .auto
    }

    func setStyle(_ style: WritingStyle, forBundleID bundleID: String) {
        appStyles[bundleID] = style.rawValue
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

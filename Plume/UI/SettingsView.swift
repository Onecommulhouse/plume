import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var transcriber: Transcriber
    @ObservedObject private var updates = UpdateManager.shared

    @State private var keyDraft = ""
    @State private var keyStatus: KeyStatus = .idle

    enum KeyStatus: Equatable {
        case idle
        case testing
        case ok
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Réglages", subtitle: "Plume s'adapte à ta façon de travailler.")

            SettingsCard(title: "Toi") {
                SettingsRow(label: "Prénom", hint: "Pour te saluer sur le tableau de bord.") {
                    TextField("Prénom", text: $settings.firstName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }

            SettingsCard(title: "Dictée") {
                SettingsRow(label: "Raccourci", hint: hotkeyHint) {
                    Picker("", selection: $settings.hotkey) {
                        ForEach(HotkeyChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }
                Divider().overlay(Theme.line)
                SettingsRow(label: "Langue", hint: "La langue dans laquelle tu dictes le plus souvent.") {
                    Picker("", selection: $settings.language) {
                        ForEach(LanguageChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                }
                Divider().overlay(Theme.line)
                SettingsRow(label: "Sons", hint: "Un petit son au début et à la fin de la dictée.") {
                    Toggle("", isOn: $settings.soundsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.gold)
                }
                Divider().overlay(Theme.line)
                SettingsRow(label: "Couper le son pendant la dictée", hint: "Musique, YouTube, vidéos… le son du Mac se coupe tant que tu maintiens la touche et revient dès que tu relâches. Ta voix est aussi mieux comprise.") {
                    Toggle("", isOn: $settings.muteWhileDictating)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.gold)
                }
                Divider().overlay(Theme.line)
                SettingsRow(label: "Garder le texte copié", hint: "Laisse la dernière dictée dans le presse-papier au lieu de remettre ce qu'il y avait avant.") {
                    Toggle("", isOn: $settings.keepInClipboard)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.gold)
                }
            }

            SettingsCard(title: "Mise au propre par Claude") {
                SettingsRow(label: "Activer", hint: "Ponctuation, « euh » retirés, corrections. Seul le texte est envoyé à Claude, jamais ta voix.") {
                    Toggle("", isOn: $settings.cleanupEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.gold)
                }
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Clé API Anthropic")
                            .font(Theme.font(14, .semibold))
                            .foregroundStyle(Theme.navy)
                        Spacer()
                        Text(settings.hasAPIKey ? "Clé enregistrée dans le trousseau" : "Aucune clé")
                            .font(Theme.font(12, .medium))
                            .foregroundStyle(settings.hasAPIKey ? Theme.navy : Theme.muted)
                    }
                    HStack(spacing: 10) {
                        SecureField(settings.hasAPIKey ? "Remplacer la clé…" : "sk-ant-…", text: $keyDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Enregistrer") {
                            settings.saveAPIKey(keyDraft)
                            keyDraft = ""
                            testKey()
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if settings.hasAPIKey {
                            Button("Tester", action: testKey)
                                .buttonStyle(PillButtonStyle(prominent: false))
                            Button("Retirer") {
                                settings.saveAPIKey("")
                                keyStatus = .idle
                            }
                            .buttonStyle(PillButtonStyle(prominent: false))
                        }
                    }
                    keyStatusView
                    Link("Créer une clé sur console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(Theme.font(12, .semibold))
                        .foregroundStyle(Theme.navy)
                    if let error = controller.lastCleanupError {
                        Text("Dernière erreur : \(error)")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            SettingsCard(title: "Autorisations") {
                PermissionRow(
                    label: "Micro",
                    granted: permissions.microphone == .granted,
                    action: { permissions.requestMicrophone() }
                )
                Divider().overlay(Theme.line)
                PermissionRow(
                    label: "Accessibilité (raccourci et collage)",
                    granted: permissions.accessibility,
                    action: { permissions.requestAccessibility() }
                )
                if !permissions.accessibility {
                    Text("Déjà activée dans Réglages Système mais Plume dit non ? Quitte Plume, retire la ligne Plume de la liste Accessibilité avec le bouton −, rouvre Plume puis clique sur Autoriser.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: "Mises à jour") {
                SettingsRow(label: "Mettre à jour automatiquement", hint: "Plume vérifie toutes les heures, télécharge la nouvelle version et se relance toute seule dès qu'aucune dictée n'est en cours. Rien à réinstaller.") {
                    Toggle("", isOn: $updates.automaticUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.gold)
                }
                Divider().overlay(Theme.line)
                SettingsRow(label: "Version installée", hint: "Plume \(updates.versionLabel)") {
                    Button("Rechercher maintenant") {
                        updates.checkForUpdates()
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(!updates.canCheckForUpdates)
                }
            }

            SettingsCard(title: "Général") {
                SettingsRow(label: "Lancer Plume au démarrage", hint: "Plume s'ouvre discrètement dans la barre des menus.") {
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.gold)
                }
                Divider().overlay(Theme.line)
                SettingsRow(label: "Modèle de transcription", hint: "Whisper large v3 turbo, exécuté sur ton Mac.") {
                    Text(modelStatus)
                        .font(Theme.font(13, .medium))
                        .foregroundStyle(Theme.navy)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Plume \(appVersion) · un outil one com")
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.muted)
                Text("Transcription locale : WhisperKit d'Argmax (licence MIT). Collage selon la disposition du clavier adapté d'OpenWhispr (licence MIT). Mises à jour : Sparkle (licence MIT). Police Montserrat (licence OFL).")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var hotkeyHint: String {
        switch settings.hotkey {
        case .fn:
            return "Dans Réglages Système > Clavier, règle « Appuyer sur 🌐 pour » sur « Ne rien faire »."
        default:
            return "Maintiens la touche, parle, relâche. Une autre touche pendant le maintien annule."
        }
    }

    private var modelStatus: String {
        switch transcriber.status {
        case .ready: return "Prêt"
        case .downloading(let fraction): return "Téléchargement \(Int(fraction * 100)) %"
        case .loading: return "Préparation…"
        case .failed: return "Indisponible"
        case .idle: return "En attente"
        }
    }

    @ViewBuilder
    private var keyStatusView: some View {
        switch keyStatus {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Test en cours…").font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        case .ok:
            Label("La clé fonctionne.", systemImage: "checkmark.circle.fill")
                .font(Theme.font(12, .semibold))
                .foregroundStyle(Theme.navy)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.font(12, .semibold))
                .foregroundStyle(Theme.navy)
        }
    }

    private func testKey() {
        guard let key = settings.apiKey, !key.isEmpty else { return }
        keyStatus = .testing
        Task {
            do {
                try await TextCleaner(apiKey: key).test()
                keyStatus = .ok
            } catch {
                keyStatus = .failed(error.localizedDescription)
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.font(13, .bold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .tracking(0.6)
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    let hint: String
    let control: Control

    init(label: String, hint: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.navy)
                Text(hint)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
    }
}

private struct PermissionRow: View {
    let label: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Theme.gold : Theme.soft)
            Text(label)
                .font(Theme.font(14, .semibold))
                .foregroundStyle(Theme.navy)
            Spacer()
            if granted {
                Text("Accordé")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.muted)
            } else {
                Button("Autoriser", action: action)
                    .buttonStyle(PillButtonStyle())
            }
        }
    }
}

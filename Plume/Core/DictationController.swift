import AppKit
import Combine

/// Chef d'orchestre : raccourci → micro → transcription locale → nettoyage Claude → collage → historique.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case cleaning
        case error(String)

        var menuBarSymbol: String {
            switch self {
            case .recording: return "waveform.circle.fill"
            case .transcribing, .cleaning: return "ellipsis.circle"
            case .error: return "exclamationmark.circle"
            case .idle: return "waveform"
            }
        }

        var isBusy: Bool {
            switch self {
            case .recording, .transcribing, .cleaning: return true
            default: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// Derniers niveaux du micro (0…1), pour la vague affichée pendant l'enregistrement.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 18)
    @Published private(set) var lastCleanupError: String?

    let settings = AppSettings()
    let store = HistoryStore()
    let transcriber = Transcriber()
    let permissions = PermissionsManager()

    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyMonitor()
    private var overlay: OverlayController?
    private var recordStart: Date?
    private var targetApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var errorResetTask: Task<Void, Never>?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        overlay = OverlayController(controller: self)

        hotkeys.hotkey = settings.hotkey
        hotkeys.onPress = { [weak self] in
            Task { @MainActor in self?.beginRecording() }
        }
        hotkeys.onRelease = { [weak self] in
            Task { @MainActor in self?.endRecording() }
        }
        hotkeys.onInterrupt = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }

        // Appelé depuis le fil audio : on repasse sur le fil principal.
        recorder.onLevel = { @Sendable [weak self] rms in
            Task { @MainActor in self?.pushLevel(rms) }
        }

        permissions.onAccessibilityGranted = { [weak self] in
            // Les moniteurs globaux doivent être recréés une fois l'accès accordé.
            self?.hotkeys.start()
        }
        permissions.refresh()
        permissions.startPolling()
        hotkeys.start()

        settings.$hotkey
            .sink { [weak self] choice in self?.hotkeys.hotkey = choice }
            .store(in: &cancellables)

        // Relaie les changements des sous-objets pour rafraîchir les vues qui observent le contrôleur.
        transcriber.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        permissions.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Task { await transcriber.prepare(model: PlumeConfig.whisperModel) }
    }

    func retryModel() {
        Task { await transcriber.prepare(model: PlumeConfig.whisperModel) }
    }

    /// Ligne d'état courte (menu de la barre des menus, bas de la barre latérale).
    var statusLine: String {
        switch phase {
        case .recording: return "J'écoute…"
        case .transcribing: return "Transcription…"
        case .cleaning: return "Mise au propre…"
        case .error(let message): return message
        case .idle: break
        }
        switch transcriber.status {
        case .downloading(let fraction): return "Téléchargement du modèle : \(Int(fraction * 100)) %"
        case .loading: return "Préparation du modèle…"
        case .failed: return "Modèle indisponible"
        case .idle: return "Démarrage…"
        case .ready: break
        }
        if !permissions.allGranted { return "Autorisations à donner" }
        return "Prêt"
    }

    var isReady: Bool {
        transcriber.status == .ready && permissions.allGranted
    }

    // MARK: - Cycle de dictée

    private func beginRecording() {
        switch phase {
        case .idle, .error: break
        default: return
        }
        guard permissions.microphone == .granted else {
            permissions.requestMicrophone()
            showError("Autorise le micro pour dicter")
            return
        }
        guard transcriber.status == .ready else {
            showError("Le modèle se prépare, encore un instant")
            return
        }

        targetApp = NSWorkspace.shared.frontmostApplication
        do {
            try recorder.start()
        } catch {
            showError(error.localizedDescription)
            return
        }
        errorResetTask?.cancel()
        recordStart = Date()
        levels = Array(repeating: 0, count: levels.count)
        phase = .recording
        overlay?.show()
        if settings.soundsEnabled { NSSound(named: "Tink")?.play() }
    }

    private func endRecording() {
        guard phase == .recording, let start = recordStart else { return }
        let samples = recorder.stop()
        let duration = Date().timeIntervalSince(start)
        recordStart = nil

        // Appui trop court : on considère que c'était involontaire.
        guard duration >= 0.4, samples.count >= 8_000 else {
            phase = .idle
            overlay?.hide()
            return
        }
        if settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        phase = .transcribing
        Task { await process(samples: samples, duration: duration) }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        _ = recorder.stop()
        recordStart = nil
        phase = .idle
        overlay?.hide()
    }

    private func process(samples: [Float], duration: TimeInterval) async {
        do {
            let raw = try await transcriber.transcribe(
                samples,
                language: settings.language.whisperCode,
                vocabulary: settings.vocabulary
            )
            let transcript = Hallucinations.clean(raw)
            guard !transcript.isEmpty else {
                phase = .idle
                overlay?.hide()
                return
            }

            var finalText = transcript
            var cleaned = false
            if settings.cleanupEnabled, let key = settings.apiKey, !key.isEmpty {
                phase = .cleaning
                do {
                    finalText = try await TextCleaner(apiKey: key).clean(
                        transcript,
                        vocabulary: settings.vocabulary,
                        appName: targetApp?.localizedName
                    )
                    cleaned = true
                    lastCleanupError = nil
                } catch {
                    // Sans réseau ou clé invalide : on colle la transcription brute plutôt que rien.
                    lastCleanupError = error.localizedDescription
                }
            }

            overlay?.hide()
            Paster.paste(finalText, keepInClipboard: settings.keepInClipboard)
            store.add(Dictation(
                date: Date(),
                text: finalText,
                rawText: transcript,
                words: finalText.wordCount,
                duration: duration,
                appName: targetApp?.localizedName,
                appBundleID: targetApp?.bundleIdentifier,
                cleaned: cleaned
            ))
            phase = .idle
        } catch {
            showError("La transcription a échoué")
        }
    }

    private func showError(_ message: String) {
        phase = .error(message)
        overlay?.show()
        errorResetTask?.cancel()
        errorResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if case .error = self.phase {
                    self.phase = .idle
                    self.overlay?.hide()
                }
            }
        }
    }

    private func pushLevel(_ rms: Float) {
        guard phase == .recording else { return }
        // Le RMS de la voix tourne autour de 0,01–0,2 : on l'étire pour une vague lisible.
        let normalized = min(1, max(0, CGFloat(sqrt(Double(rms)) * 2.2)))
        levels.removeFirst()
        levels.append(normalized)
    }
}

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
    /// Ce que Plume entend, affiché en direct sous forme de bulle pendant la dictée.
    @Published private(set) var liveText = ""
    /// Mode mains libres (double appui) : la dictée continue sans garder la touche enfoncée.
    @Published private(set) var isHandsFree = false
    @Published private(set) var recordingStartedAt: Date?

    let settings = AppSettings()
    let store = HistoryStore()
    let transcriber = Transcriber()
    let permissions = PermissionsManager()

    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyMonitor()
    private let ducker = AudioDucker()
    private var duckTask: Task<Void, Never>?
    private var overlay: OverlayController?
    private var recordStart: Date?
    private var targetApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var errorResetTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var handsFreeTimeout: Task<Void, Never>?
    private var lastQuickTapEnd: Date?
    private var ignoreNextRelease = false
    private var started = false

    /// Durée d'audio retranscrite à chaque rafraîchissement du texte en direct (les 20 dernières secondes).
    private static let previewWindow = 16_000 * 20
    /// Délai maximal entre deux appuis pour passer en mains libres.
    private static let doubleTapDelay: TimeInterval = 0.45
    /// Sécurité : une dictée mains libres s'arrête d'elle-même au bout de 10 minutes.
    private static let handsFreeLimit: UInt64 = 600

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        overlay = OverlayController(controller: self)
        AudioDucker.restorePendingIfNeeded()

        hotkeys.hotkey = settings.hotkey
        hotkeys.onPress = { [weak self] in
            Task { @MainActor in self?.hotkeyPressed() }
        }
        hotkeys.onRelease = { [weak self] in
            Task { @MainActor in self?.hotkeyReleased() }
        }
        hotkeys.onInterrupt = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }
        hotkeys.onEscape = { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.cancelRecording()
            }
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

    // MARK: - Raccourci : maintien, ou double appui pour les mains libres

    private func hotkeyPressed() {
        // En mains libres, un nouvel appui termine la dictée.
        if phase == .recording, isHandsFree {
            ignoreNextRelease = true
            endRecording()
            return
        }
        let isDoubleTap = settings.handsFreeEnabled
            && (lastQuickTapEnd.map { Date().timeIntervalSince($0) < Self.doubleTapDelay } ?? false)
        lastQuickTapEnd = nil
        ignoreNextRelease = false
        beginRecording(handsFree: isDoubleTap)
    }

    private func hotkeyReleased() {
        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        // Double appui : on continue d'écouter une fois la touche relâchée.
        if phase == .recording, isHandsFree { return }
        endRecording()
    }

    // MARK: - Cycle de dictée

    private func beginRecording(handsFree: Bool = false) {
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
        recordingStartedAt = recordStart
        isHandsFree = handsFree
        levels = Array(repeating: 0, count: levels.count)
        phase = .recording
        overlay?.show()
        startPreview()
        if handsFree {
            handsFreeTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.handsFreeLimit * 1_000_000_000)
                guard !Task.isCancelled, let self, self.phase == .recording, self.isHandsFree else { return }
                self.endRecording()
            }
        }
        if settings.soundsEnabled { NSSound(named: "Tink")?.play() }
        if settings.muteWhileDictating {
            // On laisse le petit son de départ se jouer avant de couper le reste.
            let delay: UInt64 = settings.soundsEnabled ? 150_000_000 : 0
            duckTask = Task { [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                guard !Task.isCancelled, let self, self.phase == .recording else { return }
                self.ducker.duck()
            }
        }
    }

    /// À la fermeture de l'app : on ne laisse jamais le Mac muet.
    func prepareForQuit() {
        if phase == .recording { _ = recorder.stop() }
        restoreAudio()
    }

    /// Rend le son du Mac (appelé dès que la touche est relâchée ou la dictée annulée).
    private func restoreAudio() {
        duckTask?.cancel()
        duckTask = nil
        ducker.restore()
    }

    private func endRecording() {
        guard phase == .recording, let start = recordStart else { return }
        let samples = recorder.stop()
        let duration = Date().timeIntervalSince(start)
        let pendingPreview = finishRecordingSession()
        restoreAudio()

        // Appui trop court : on considère que c'était involontaire… ou le premier d'un double appui.
        guard duration >= 0.4, samples.count >= 8_000 else {
            if duration < 0.35 { lastQuickTapEnd = Date() }
            liveText = ""
            phase = .idle
            overlay?.hide()
            return
        }
        if settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        phase = .transcribing
        Task {
            // Le texte en direct utilise le même modèle : on attend qu'il ait fini avant la transcription finale.
            await pendingPreview?.value
            await process(samples: samples, duration: duration)
        }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        _ = recorder.stop()
        _ = finishRecordingSession()
        restoreAudio()
        liveText = ""
        phase = .idle
        overlay?.hide()
    }

    /// Remet à zéro l'état propre à l'enregistrement. Renvoie le rafraîchissement du texte en direct encore en cours.
    private func finishRecordingSession() -> Task<Void, Never>? {
        recordStart = nil
        recordingStartedAt = nil
        isHandsFree = false
        handsFreeTimeout?.cancel()
        handsFreeTimeout = nil
        let preview = previewTask
        preview?.cancel()
        previewTask = nil
        return preview
    }

    // MARK: - Texte en direct

    /// Toutes les ~0,5 s, retranscrit les 20 dernières secondes pour montrer ce que Plume entend.
    private func startPreview() {
        liveText = ""
        guard settings.showLiveText else { return }
        let language = settings.language.whisperCode
        let vocabulary = settings.vocabulary
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            while !Task.isCancelled {
                guard let self, self.phase == .recording else { return }
                let all = self.recorder.snapshot()
                if all.count >= 12_000 {
                    let clipped = all.count > Self.previewWindow
                    let samples = clipped ? Array(all.suffix(Self.previewWindow)) : all
                    let text = (try? await self.transcriber.transcribe(
                        samples,
                        language: language,
                        vocabulary: vocabulary,
                        preview: true
                    )) ?? ""
                    guard !Task.isCancelled, self.phase == .recording else { return }
                    let heard = Hallucinations.clean(text)
                    if !heard.isEmpty {
                        self.liveText = clipped ? "… " + heard : heard
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func process(samples: [Float], duration: TimeInterval) async {
        defer { liveText = "" }
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

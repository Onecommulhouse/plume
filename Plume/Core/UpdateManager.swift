import Foundation
import Combine
import Sparkle

/// Mises à jour automatiques (Sparkle).
/// Plume regarde toutes les heures s'il existe une nouvelle version, la télécharge en arrière-plan,
/// puis s'installe et se relance d'elle-même dès qu'aucune dictée n'est en cours. Rien à réinstaller.
@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isInstalling = false
    /// Installation automatique (activée par défaut). Désactivée : Plume propose la mise à jour dans une fenêtre.
    @Published var automaticUpdates = true {
        didSet { controller?.updater.automaticallyDownloadsUpdates = automaticUpdates }
    }

    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?
    private var waitTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
    }

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        let updater = controller.updater
        // Les vérifications automatiques restent toujours actives ; seul l'auto-install est réglable.
        updater.automaticallyChecksForUpdates = true
        automaticUpdates = updater.automaticallyDownloadsUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)
    }

    /// Vérification à la demande (menu ou réglages) : affiche le résultat dans une fenêtre.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: - SPUUpdaterDelegate

    /// Une mise à jour a été téléchargée en arrière-plan. Au lieu d'attendre que Plume soit quittée
    /// (elle tourne en continu dans la barre des menus), on l'installe dès que Plume est au repos.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        pendingInstall = immediateInstallHandler
        installWhenIdle()
        return true
    }

    private func installWhenIdle() {
        waitTask?.cancel()
        waitTask = Task { @MainActor [weak self] in
            // On attend la fin de toute dictée, puis quelques secondes de calme.
            var calmSeconds = 0
            while calmSeconds < 5 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                calmSeconds = DictationController.shared.phase.isBusy ? 0 : calmSeconds + 1
            }
            guard let self, let install = self.pendingInstall else { return }
            self.pendingInstall = nil
            self.isInstalling = true
            DictationController.shared.prepareForQuit()
            install()
        }
    }
}

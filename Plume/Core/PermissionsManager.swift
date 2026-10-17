import AppKit
import AVFoundation

/// Suit les deux autorisations dont Plume a besoin : le micro et l'accessibilité (pour lire le raccourci et coller).
@MainActor
final class PermissionsManager: ObservableObject {
    enum MicrophoneState {
        case granted
        case denied
        case notDetermined
    }

    @Published private(set) var microphone: MicrophoneState = .notDetermined
    @Published private(set) var accessibility = false

    /// Appelé quand l'accès Accessibilité vient d'être accordé (il faut alors relancer l'écoute du clavier).
    var onAccessibilityGranted: (() -> Void)?

    private var timer: Timer?

    var allGranted: Bool { microphone == .granted && accessibility }

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .granted
        case .notDetermined: microphone = .notDetermined
        default: microphone = .denied
        }
        let trusted = AXIsProcessTrusted()
        if trusted && !accessibility {
            accessibility = true
            onAccessibilityGranted?()
        } else if !trusted {
            accessibility = false
        }
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        default:
            openSettings("Privacy_Microphone")
        }
    }

    func requestAccessibility() {
        // Affiche la demande système puis ouvre le bon panneau des Réglages.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

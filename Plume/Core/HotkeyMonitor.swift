import AppKit

/// Surveille la touche de dictée (maintenir = enregistrer, relâcher = écrire).
/// Les moniteurs globaux d'AppKit ne reçoivent les touches des autres apps
/// qu'une fois l'accès « Accessibilité » accordé à Plume.
final class HotkeyMonitor {
    var hotkey: HotkeyChoice = .rightOption {
        didSet { if hotkey != oldValue { isDown = false } }
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Une autre touche a été tapée pendant le maintien (ex. Option + lettre pour un caractère spécial).
    var onInterrupt: (() -> Void)?
    /// Touche Échap, à tout moment (annule une dictée en mode mains libres).
    var onEscape: (() -> Void)?

    private var monitors: [Any] = []
    private var isDown = false

    func start() {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlags(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlags(event)
            return event
        }) {
            monitors.append(local)
        }
        if let globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event)
        }) {
            monitors.append(globalKeys)
        }
        if let localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }) {
            monitors.append(localKeys)
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        isDown = false
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard event.keyCode == hotkey.keyCode else {
            // Un autre modificateur ajouté pendant le maintien : on annule.
            if isDown {
                isDown = false
                onInterrupt?()
            }
            return
        }

        let pressed = flags.contains(hotkey.flag)
        if pressed && !isDown {
            isDown = true
            onPress?()
        } else if !pressed && isDown {
            isDown = false
            onRelease?()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { // Échap
            isDown = false
            onEscape?()
            return
        }
        guard isDown else { return }
        isDown = false
        onInterrupt?()
    }
}

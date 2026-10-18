import AppKit
import ApplicationServices

/// Contexte de la fenêtre où le texte sera collé.
enum WindowContext {
    /// Titre de la fenêtre active d'une app (objet du mail, nom de la conversation…),
    /// lu grâce à l'accès Accessibilité. Sert seulement d'indice à Claude pour le ton.
    static func focusedWindowTitle(of app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier, AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(pid)
        // Une app qui ne répond pas ne doit jamais retarder la dictée.
        AXUIElementSetMessagingTimeout(element, 0.2)

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let window = windowValue as! AXUIElement

        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
              let title = titleValue as? String else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != app?.localizedName else { return nil }
        return String(trimmed.prefix(120))
    }
}

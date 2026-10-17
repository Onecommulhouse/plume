import AppKit
import Carbon.HIToolbox

/// Colle le texte dans l'app active : presse-papier + ⌘V simulé, puis restauration du presse-papier.
///
/// La recherche de la touche « V » selon la disposition du clavier (AZERTY, QWERTY, Dvorak…)
/// est adaptée de `resources/macos-fast-paste.swift` du projet OpenWhispr
/// (https://github.com/OpenWhispr/openwhispr), sous licence MIT — voir LICENSES/OpenWhispr-MIT.txt.
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @MainActor
    static func paste(_ text: String, keepInClipboard: Bool) {
        let pasteboard = NSPasteboard.general
        let saved = keepInClipboard ? nil : snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Signale aux gestionnaires de presse-papier que ce contenu est éphémère.
        if !keepInClipboard {
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }
        let changeCount = pasteboard.changeCount

        sendCommand(character: "v")

        guard let saved, !saved.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // On ne restaure que si personne n'a recopié autre chose entre-temps.
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func sendCommand(character: String) {
        let keyCode = lookupVirtualKey(for: character) ?? CGKeyCode(kVK_ANSI_V)
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        usleep(8_000)
        up.post(tap: .cgSessionEventTap)
    }

    private static func keyboardLayoutData(from inputSource: TISInputSource?) -> Data? {
        guard let inputSource,
              let pointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    private static func lookupVirtualKey(for character: String) -> CGKeyCode? {
        guard let layoutData = keyboardLayoutData(from: TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue())
            ?? keyboardLayoutData(from: TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()) else {
            return nil
        }
        let commandModifierState = UInt32(cmdKey) >> 8

        return layoutData.withUnsafeBytes { rawBuffer -> CGKeyCode? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            let keyboardLayout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)

            for keyCode in 0..<128 {
                deadKeyState = 0
                let status = UCKeyTranslate(
                    keyboardLayout,
                    UInt16(keyCode),
                    UInt16(kUCKeyActionDisplay),
                    commandModifierState,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )
                if status == noErr, String(utf16CodeUnits: chars, count: length) == character {
                    return CGKeyCode(keyCode)
                }
            }
            return nil
        }
    }
}

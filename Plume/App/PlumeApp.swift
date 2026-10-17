import SwiftUI

@main
struct PlumeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = DictationController.shared

    var body: some Scene {
        Window("Plume", id: "main") {
            MainView()
                .environmentObject(controller)
                .environmentObject(controller.settings)
                .environmentObject(controller.store)
                .environmentObject(controller.transcriber)
                .environmentObject(controller.permissions)
                .frame(minWidth: 1000, minHeight: 680)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 820)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(controller.store)
                .environmentObject(controller.settings)
        } label: {
            Image(systemName: controller.phase.menuBarSymbol)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.registerBundledFonts()
        Task { @MainActor in
            DictationController.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            DictationController.shared.prepareForQuit()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Plume keeps listening for the shortcut from the menu bar.
        false
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var store: HistoryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.statusLine)
        Divider()
        Button("Ouvrir Plume") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")
        Button("Copier la dernière dictée") {
            if let last = store.items.first {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(last.text, forType: .string)
            }
        }
        .disabled(store.items.isEmpty)
        Divider()
        Button("Quitter Plume") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

import SwiftUI
import AppKit
import UserNotifications

struct OsaHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var hub = Hub.shared

    var body: some Scene {
        Window("OsaHUB", id: "main") {
            RootView()
                .environmentObject(hub)
                .frame(minWidth: 880, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Rechercher des mises à jour") { Task { await Hub.shared.refresh() } }
                    .keyboardShortcut("r")
                Button("Recherche rapide") { Hub.shared.palette.toggle() }
                    .keyboardShortcut("k")
            }
        }

        MenuBarExtra {
            MenuContent().environmentObject(hub)
        } label: {
            Image(systemName: hub.updates.isEmpty ? "square.grid.2x2" : "square.grid.2x2.fill")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Hub.shared.start()
    }

    /// Fenêtre fermée : OsaHUB reste dans la barre des menus pour surveiller les mises à jour.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    /// Une feuille ouverte (les nouveautés) faisait refuser « Quitter » envoyé par AppleScript ou
    /// par une mise à jour : on ferme les feuilles puis on quitte.
    func applicationWillFinishLaunching(_ n: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(quitEvent(_:reply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    @objc private func quitEvent(_ e: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        closeSheets()
        NSApp.terminate(nil)
    }

    private func closeSheets() {
        for w in NSApp.windows { if let s = w.attachedSheet { w.endSheet(s) } }
    }

    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        closeSheets()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Hub.shared.openMain?() }
        return true
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let id = r.notification.request.content.userInfo["app"] as? String
        DispatchQueue.main.async {
            Hub.shared.openMain?()
            Hub.shared.showChangelog(id: id)
        }
        done()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

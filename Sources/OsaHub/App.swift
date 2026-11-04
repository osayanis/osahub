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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var suite: SuiteHub?
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Hub.shared.start()
        // OSAHUB_NO_SUITE=1 : instance de test (captures) — ni icône dans la barre des menus, ni
        // messages à OsaWallpaper, pour ne pas déranger le vrai OsaHUB.
        guard ProcessInfo.processInfo.environment["OSAHUB_NO_SUITE"] == nil else { watchWindows(); return }
        let suite = SuiteHub()
        suite.start()
        self.suite = suite
        statusMenu = StatusMenu(suite: suite)
        watchWindows()
        Hub.shared.announceSelfUpdate()
    }

    func applicationWillTerminate(_ n: Notification) { suite?.stop() }

    /// Fenêtre fermée : OsaHUB reste dans la barre des menus pour surveiller les mises à jour.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    /// Fenêtre fermée : OsaHUB quitte le Dock mais continue en arrière-plan (barre des menus) ;
    /// elle y revient dès qu'une fenêtre se rouvre.
    private func watchWindows() {
        let nc = NotificationCenter.default
        func isAppWindow(_ w: NSWindow) -> Bool { w.styleMask.contains(.titled) && w.sheetParent == nil && !(w is NSPanel) }
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, isAppWindow(w), NSApp.activationPolicy() != .regular else { return }
            NSApp.setActivationPolicy(.regular)
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let closing = n.object as? NSWindow, isAppWindow(closing) else { return }
            DispatchQueue.main.async {
                let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && isAppWindow($0) }
                if !others {
                    NSApp.setActivationPolicy(.accessory)
                    MainActor.assumeIsolated { Hub.shared.autoUpdateSelfIfIdle() }
                }
            }
        }
    }

    /// Une feuille ouverte (les nouveautés) faisait refuser « Quitter » envoyé par AppleScript ou
    /// par une mise à jour : on ferme les feuilles puis on quitte.
    func applicationWillFinishLaunching(_ n: Notification) {
        // relancé par une mise à jour automatique : pas d'icône dans le Dock
        if Hub.autoUpdated { NSApp.setActivationPolicy(.accessory) }
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

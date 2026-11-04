import AppKit

// La suite Osa parle d'une appli à l'autre par notifications distribuées (même session, pas de
// serveur). Côté OsaHUB :
//   com.osalabs.suite.hello            « je viens d'arriver » → chacun renvoie son état
//   com.osalabs.suite.hub              OsaHUB : running (Bool). Tant qu'il tourne, OsaWallpaper
//                                      retire son icône de la barre des menus.
//   com.osalabs.suite.wallpaperMenu    OsaWallpaper → OsaHUB : info ([String]), canPreview (Bool)
//   com.osalabs.suite.wallpaperAction  OsaHUB → OsaWallpaper : action (open | preview | settings | quit)
enum Suite {
    static let hello = Notification.Name("com.osalabs.suite.hello")
    static let hub = Notification.Name("com.osalabs.suite.hub")
    static let wallpaperMenu = Notification.Name("com.osalabs.suite.wallpaperMenu")
    static let wallpaperAction = Notification.Name("com.osalabs.suite.wallpaperAction")
    static let wallpaperID = "com.osalabs.osawallpaper"

    static func post(_ name: Notification.Name, _ info: [String: Any] = [:]) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
    }
}

@MainActor
final class SuiteHub {
    struct WallpaperMenu { var info: [String]; var canPreview: Bool }
    private(set) var wallpaper: WallpaperMenu?
    var wallpaperRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Suite.wallpaperID).isEmpty
    }
    private var tokens: [NSObjectProtocol] = []

    func start() {
        let dc = DistributedNotificationCenter.default()
        tokens.append(dc.addObserver(forName: Suite.hello, object: nil, queue: .main) { [weak self] _ in self?.announce() })
        tokens.append(dc.addObserver(forName: Suite.wallpaperMenu, object: nil, queue: .main) { [weak self] n in
            let info = (n.userInfo?["info"] as? [String] ?? []).prefix(4).map { String($0.prefix(80)) }
            self?.wallpaper = WallpaperMenu(info: Array(info), canPreview: n.userInfo?["canPreview"] as? Bool ?? false)
        })
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Suite.wallpaperID { self?.wallpaper = nil }
        })
        announce()
        Suite.post(Suite.hello, ["app": "osahub"])
    }

    /// « OsaHUB est là » : OsaWallpaper retire son icône et envoie ses options.
    func announce() { Suite.post(Suite.hub, ["running": true]) }

    func requestWallpaperMenu() { announce() }

    func wallpaperAction(_ action: String) { Suite.post(Suite.wallpaperAction, ["action": action]) }

    /// À la fermeture : OsaWallpaper remet son icône.
    func stop() { Suite.post(Suite.hub, ["running": false]) }
}

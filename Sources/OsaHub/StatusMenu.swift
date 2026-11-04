import AppKit

// La barre des menus d'OsaHUB : la même mascotte qui se promène qu'OsaWallpaper, et un menu
// reconstruit à chaque ouverture. Si OsaWallpaper est installé, ses options y sont aussi : il
// retire alors sa propre icône tant qu'OsaHUB tourne (voir Suite.swift), pour n'en garder qu'une.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var mascot: MenuMascot?
    private let hub = Hub.shared
    private let suite: SuiteHub

    init(suite: SuiteHub) {
        self.suite = suite
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        if let b = item.button { mascot = MenuMascot(button: b) }
    }

    func menuWillOpen(_ menu: NSMenu) { suite.requestWallpaperMenu() }

    /// Ouvre la fenêtre : OsaHUB revient dans le Dock et passe devant.
    static func show() {
        NSApp.setActivationPolicy(.regular)
        Hub.shared.openMain?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, enabled: Bool = true, key: String = "", _ run: (() -> Void)? = nil) {
            let i = ClosureItem(title: title, keyEquivalent: key, run: run)
            i.isEnabled = enabled && run != nil
            menu.addItem(i)
        }
        func header(_ title: String) {
            if #available(macOS 14, *) { menu.addItem(.sectionHeader(title: title)) } else { add(title, enabled: false) }
        }

        // ── OsaHUB ──
        if hub.updates.isEmpty {
            add(hub.checking ? "Recherche des mises à jour…" : "Toutes tes apps sont à jour", enabled: false)
        } else {
            for e in hub.updates {
                add("\(e.name) \(hub.releases[e.id]?.version ?? "") : voir les nouveautés") { [hub] in
                    StatusMenu.show(); hub.changelog = e
                }
            }
            if hub.updates.count > 1 { add("Tout mettre à jour") { [hub] in hub.updateAll() } }
        }
        let installed = hub.entries.filter { hub.installed[$0.id] != nil }
        if !installed.isEmpty {
            menu.addItem(.separator())
            header("Ouvrir")
            for e in installed {
                add(hub.running.contains(e.id) ? "\(e.name)  ·  ouverte" : e.name) { [hub] in hub.open(e) }
            }
        }

        // ── OsaWallpaper (fusionné) ──
        if let wp = hub.entries.first(where: { $0.id == "osawallpaper" }), hub.installed[wp.id] != nil {
            menu.addItem(.separator())
            header("OsaWallpaper")
            if let w = suite.wallpaper, suite.wallpaperRunning {
                for line in w.info { add(line, enabled: false) }
                add("Ouvrir OsaWallpaper…") { [suite] in suite.wallpaperAction("open") }
                add(w.canPreview ? "Aperçu de l’écran verrouillé" : "Aperçu (lance un morceau)", enabled: w.canPreview) { [suite] in
                    suite.wallpaperAction("preview")
                }
                add("Réglages d’OsaWallpaper…") { [suite] in suite.wallpaperAction("settings") }
                add("Quitter OsaWallpaper") { [suite] in suite.wallpaperAction("quit") }
            } else {
                add("Lancer OsaWallpaper") { [hub] in hub.open(wp) }
            }
        }

        menu.addItem(.separator())
        add("Ouvrir OsaHUB", key: "o") { StatusMenu.show() }
        add("Recherche rapide…") { [hub] in StatusMenu.show(); hub.palette = true }
        add("Rechercher des mises à jour") { [hub] in Task { await hub.refresh() } }
        menu.addItem(.separator())
        add("Quitter OsaHUB", key: "q") { NSApp.terminate(nil) }
    }
}

/// Élément de menu qui exécute une fermeture.
final class ClosureItem: NSMenuItem {
    private let run: (() -> Void)?
    init(title: String, keyEquivalent: String, run: (() -> Void)?) {
        self.run = run
        super.init(title: title, action: run == nil ? nil : #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run?() }
}

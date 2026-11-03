import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

/// L'état d'OsaHUB : le catalogue, ce qui est installé, les dernières versions, les installations en cours.
@MainActor
final class Hub: ObservableObject {
    static let shared = Hub()
    static let selfRepo = "osayanis/osahub"
    static let selfAsset = "OsaHUB.zip"

    struct Installed: Equatable {
        var version: String
        var url: URL
    }

    enum Job: Equatable {
        case downloading(Double)
        case installing
        case done
        case failed(String)
    }

    @Published var entries: [AppEntry] = Catalog.builtIn
    @Published var installed: [String: Installed] = [:]
    @Published var releases: [String: Release] = [:]
    /// Apps dont la release a bien été cherchée (avec ou sans résultat).
    @Published var checked: Set<String> = []
    @Published var checking = false
    @Published var offline = false
    /// Limite de l'API GitHub atteinte : jusqu'à quand (les versions viennent du cache).
    @Published var limitedUntil: Date?
    @Published var lastCheck: Date?
    @Published var jobs: [String: Job] = [:]
    /// L'app dont on montre les nouveautés (feuille par-dessus tout).
    @Published var changelog: AppEntry?
    @Published var selfRelease: Release?
    @Published var selfJob: Job?
    @Published var splashDone = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Apps de la suite ouvertes en ce moment.
    @Published var running: Set<String> = []
    /// Les versions publiées de chaque app (chargées à l'ouverture de sa fiche).
    @Published var history: [String: [Release]] = [:]
    /// Apps mises à jour toutes seules (si elles ne sont pas ouvertes).
    @Published var autoUpdate: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "auto") ?? [])
    @Published var services: [String: ServiceState] = [:]
    /// La palette ⌘K est ouverte.
    @Published var palette = false
    /// L'app dont on demande confirmation avant de la mettre à la Corbeille.
    @Published var uninstallAsk: AppEntry?

    enum ServiceState: Equatable { case unknown, up(Int), down }
    struct Service: Identifiable {
        let id: String
        let name: String
        let url: URL
        let symbol: String
    }
    /// Les sites OsaLabs, dont OsaHUB montre l'état.
    static let serviceList = [
        Service(id: "hub", name: "osalabs.fr", url: URL(string: "https://osalabs.fr")!, symbol: "globe"),
        Service(id: "osadrop", name: "OsaDrop", url: URL(string: "https://osadrop.osalabs.fr")!, symbol: "paperplane.fill"),
        Service(id: "osacast", name: "OsaCast", url: URL(string: "https://osacast.osalabs.fr")!, symbol: "play.tv.fill"),
        Service(id: "osaparty", name: "OsaParty", url: URL(string: "https://osaparty.osalabs.fr")!, symbol: "music.note.house.fill"),
    ]

    var openMain: (() -> Void)?
    private var timer: Timer?
    private var serviceTimer: Timer?
    private let defaults = UserDefaults.standard

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var updates: [AppEntry] { entries.filter { hasUpdate($0) } }

    func hasUpdate(_ e: AppEntry) -> Bool {
        guard let i = installed[e.id], let r = releases[e.id], r.zip != nil else { return false }
        return Version.isNewer(r.version, than: i.version)
    }

    /// Pas encore publiée : le dépôt n'a pas de release avec l'archive de l'app.
    func isComingSoon(_ e: AppEntry) -> Bool {
        checked.contains(e.id) && releases[e.id]?.zip == nil && !offline
    }

    // MARK: Vérifications

    func start() {
        URLCache.shared = URLCache(memoryCapacity: 60 << 20, diskCapacity: 300 << 20)
        scanInstalled()
        Task { await refresh() }
        // Toutes les 6 heures : l'API GitHub sans compte autorise 60 requêtes par heure.
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await Hub.shared.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Hub.shared.scanInstalled() }
        }
        // une app de la suite s'ouvre ou se ferme
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Hub.shared.scanRunning() }
            }
        }
        scanRunning()
        Task { await pingServices() }
        serviceTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await Hub.shared.pingServices() }
        }
    }

    func scanRunning() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let r = Set(entries.filter { ids.contains($0.bundleId) }.map(\.id))
        if r != running { running = r }
    }

    /// Chaque site est appelé une fois ; « en ligne » s'il répond sans erreur serveur.
    func pingServices() async {
        await withTaskGroup(of: (String, ServiceState).self) { group in
            for s in Self.serviceList {
                let url = s.url, id = s.id
                group.addTask {
                    var req = URLRequest(url: url)
                    req.httpMethod = "HEAD"
                    req.timeoutInterval = 8
                    req.cachePolicy = .reloadIgnoringLocalCacheData
                    let t0 = Date()
                    guard let (_, resp) = try? await URLSession.shared.data(for: req),
                          let code = (resp as? HTTPURLResponse)?.statusCode, code < 500 else { return (id, .down) }
                    return (id, .up(Int(Date().timeIntervalSince(t0) * 1000)))
                }
            }
            for await (id, state) in group { services[id] = state }
        }
    }

    /// Cherche chaque app : d'abord dans Applications (là où OsaHUB installe), puis là où
    /// macOS la connaît (une copie de développement, par exemple).
    /// L'Info.plist lu sur le disque (Bundle(url:) le garde en cache : après un remplacement,
    /// il rendait encore l'ancienne version).
    static func info(_ app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    func scanInstalled() {
        var found: [String: Installed] = [:]
        for e in entries {
            let candidates = [
                URL(fileURLWithPath: "/Applications/\(e.name).app"),
                Installer.home.appendingPathComponent("Applications/\(e.name).app"),
            ] + [NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundleId)].compactMap { $0 }
            for url in candidates {
                guard let info = Hub.info(url), info["CFBundleIdentifier"] as? String == e.bundleId else { continue }
                var v = info["CFBundleShortVersionString"] as? String ?? "0"
                // Une app dont l'Info.plist ne suit pas ses versions (OsaNotch ≤ 1.0.4 disait 0.1) :
                // si c'est toujours la copie qu'OsaHUB a posée, sa version est celle de la release.
                if let rec = defaults.dictionary(forKey: installedKey(e.id)) as? [String: String],
                   rec["plist"] == v, rec["path"] == url.path, let rel = rec["release"],
                   Version.isNewer(rel, than: v) {
                    v = rel
                }
                found[e.id] = Installed(version: v, url: url)
                break
            }
        }
        if found != installed { installed = found }
    }

    func refresh() async {
        guard !checking else { return }
        checking = true
        defer { checking = false; lastCheck = Date() }

        if let remote = await Catalog.fetchRemote() { entries = remote }
        scanInstalled()

        var failures = 0
        var limited: Date?? = nil
        GitHub.RateLimit.until = nil
        await withTaskGroup(of: (String, Release?, Bool).self) { group in
            for e in entries {
                let repo = e.repo, asset = e.asset, id = e.id
                group.addTask {
                    do { return (id, try await GitHub.latest(repo: repo, asset: asset), true) }
                    catch let e as GitHub.RateLimited { return ("__limite:\(e.until?.timeIntervalSince1970 ?? 0)", nil, false) }
                    catch { return (id, nil, false) }
                }
            }
            group.addTask {
                do { return ("__osahub", try await GitHub.latest(repo: Hub.selfRepo, asset: Hub.selfAsset), true) }
                catch { return ("__osahub", nil, false) }
            }
            for await (id, release, ok) in group {
                if id.hasPrefix("__limite:") {
                    let t = Double(id.dropFirst(9)) ?? 0
                    limited = .some(t > 0 ? Date(timeIntervalSince1970: t) : nil)
                }
                if !ok { failures += 1; continue }
                if id == "__osahub" {
                    selfRelease = release.flatMap { Version.isNewer($0.version, than: Hub.version) && $0.zip != nil ? $0 : nil }
                    continue
                }
                checked.insert(id)
                releases[id] = release
            }
        }
        if let l = limited { limitedUntil = l ?? Date().addingTimeInterval(3600) } else { limitedUntil = GitHub.RateLimit.until }
        offline = failures > entries.count / 2 && limited == nil
        scanRunning()
        announce()
        // mises à jour automatiques : seulement les apps fermées (on ne coupe personne)
        for e in updates where autoUpdate.contains(e.id) && !running.contains(e.id) && jobs[e.id] == nil {
            install(e)
        }
    }

    // MARK: Nouveautés

    private func seenKey(_ id: String) -> String { "vu.\(id)" }
    private func installedKey(_ id: String) -> String { "installe.\(id)" }
    private func notifiedKey(_ id: String) -> String { "notifie.\(id)" }

    /// Nouvelle version d'une app installée : on montre ses nouveautés (une fois par version),
    /// et une notification si OsaHUB est en arrière-plan.
    private func announce() {
        let fresh = updates.filter { defaults.string(forKey: seenKey($0.id)) != releases[$0.id]?.version && !autoUpdate.contains($0.id) }
        if changelog == nil, let first = fresh.first {
            changelog = first
        }
        guard !NSApp.isActive else { return }
        for e in fresh {
            guard let r = releases[e.id], defaults.string(forKey: notifiedKey(e.id)) != r.version else { continue }
            defaults.set(r.version, forKey: notifiedKey(e.id))
            notify(e, r)
        }
    }

    private func notify(_ e: AppEntry, _ r: Release) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "\(e.name) \(r.version) est disponible"
            c.body = Notes.summary(r.notes) ?? "Ouvre OsaHUB pour voir les nouveautés."
            c.userInfo = ["app": e.id]
            center.add(UNNotificationRequest(identifier: "maj.\(e.id).\(r.version)", content: c, trigger: nil))
        }
    }

    func showChangelog(id: String?) {
        guard let id, let e = entries.first(where: { $0.id == id }) else { return }
        changelog = e
    }

    /// La feuille des nouveautés est fermée : cette version est vue, on passe à la suivante.
    func changelogClosed(_ e: AppEntry) {
        if let v = releases[e.id]?.version { defaults.set(v, forKey: seenKey(e.id)) }
        if changelog?.id == e.id { changelog = nil }
        let next = updates.first { defaults.string(forKey: seenKey($0.id)) != releases[$0.id]?.version }
        if let next {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                if self?.changelog == nil { self?.changelog = next }
            }
        }
    }

    // MARK: Actions

    func install(_ e: AppEntry, version chosen: Release? = nil) {
        if case .downloading = jobs[e.id] { return }
        if jobs[e.id] == .installing { return }
        let target = chosen ?? releases[e.id]
        guard let zip = target?.zip else { return }
        jobs[e.id] = .downloading(0)
        let current = installed[e.id]?.url
        Task {
            do {
                let release = target?.version
                let installedAt = try await Installer.install(e, from: zip, current: current, progress: { p in
                    Task { @MainActor in
                        if case .downloading = Hub.shared.jobs[e.id] { Hub.shared.jobs[e.id] = .downloading(p) }
                    }
                }, installing: {
                    Task { @MainActor in Hub.shared.jobs[e.id] = .installing }
                })
                if let release, let info = Hub.info(installedAt) {
                    let plist = info["CFBundleShortVersionString"] as? String ?? "0"
                    defaults.set(["release": release, "plist": plist, "path": installedAt.path], forKey: installedKey(e.id))
                }
                scanInstalled()
                scanRunning()
                jobs[e.id] = .done
                if chosen == nil, let v = releases[e.id]?.version { defaults.set(v, forKey: seenKey(e.id)) }
                try? await Task.sleep(for: .seconds(1.6))
                if changelog?.id == e.id { changelog = nil }
                try? await Task.sleep(for: .seconds(0.8))
                if jobs[e.id] == .done { jobs[e.id] = nil }
            } catch {
                jobs[e.id] = .failed(error.localizedDescription)
            }
        }
    }

    func open(_ e: AppEntry) {
        guard let url = installed[e.id]?.url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func updateAll() {
        for e in updates { install(e) }
    }

    func quitApp(_ e: AppEntry) {
        Task { _ = await Installer.quit(e.bundleId); scanRunning() }
    }

    func relaunchApp(_ e: AppEntry) {
        guard let url = installed[e.id]?.url else { return }
        Task {
            _ = await Installer.quit(e.bundleId)
            try? await Task.sleep(for: .milliseconds(300))
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            scanRunning()
        }
    }

    /// OsaHUB ne désinstalle que ce qu'il range lui-même (Applications), jamais une copie
    /// de développement trouvée ailleurs.
    func canUninstall(_ e: AppEntry) -> Bool {
        guard let url = installed[e.id]?.url else { return false }
        let dir = url.deletingLastPathComponent().standardizedFileURL.path
        return dir == "/Applications" || dir == Installer.home.appendingPathComponent("Applications").standardizedFileURL.path
    }

    /// Quitte l'app et la met à la Corbeille (récupérable).
    func uninstall(_ e: AppEntry) {
        guard canUninstall(e), let url = installed[e.id]?.url else { return }
        Task {
            _ = await Installer.quit(e.bundleId)
            do {
                _ = try await NSWorkspace.shared.recycle([url])
                defaults.removeObject(forKey: installedKey(e.id))
                defaults.removeObject(forKey: seenKey(e.id))
                autoUpdate.remove(e.id)
                defaults.set(Array(autoUpdate), forKey: "auto")
            } catch {
                jobs[e.id] = .failed("Impossible de mettre \(e.name) à la Corbeille.")
            }
            scanInstalled()
            scanRunning()
        }
    }

    func setAutoUpdate(_ e: AppEntry, _ on: Bool) {
        if on { autoUpdate.insert(e.id) } else { autoUpdate.remove(e.id) }
        defaults.set(Array(autoUpdate), forKey: "auto")
        if on, hasUpdate(e), !running.contains(e.id) { install(e) }
    }

    func loadHistory(_ e: AppEntry) {
        guard history[e.id] == nil else { return }
        Task {
            if let list = try? await GitHub.history(repo: e.repo, asset: e.asset) { history[e.id] = list }
        }
    }

    func revealInFinder(_ e: AppEntry) {
        guard let url = installed[e.id]?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func updateSelf() {
        guard let zip = selfRelease?.zip, selfJob == nil || selfJob.map({ if case .failed = $0 { return true } else { return false } }) == true else { return }
        selfJob = .downloading(0)
        Task {
            do {
                try await Installer.updateSelf(from: zip) { p in
                    Task { @MainActor in Hub.shared.selfJob = .downloading(p) }
                }
            } catch {
                selfJob = .failed(error.localizedDescription)
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

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
    @Published var lastCheck: Date?
    @Published var jobs: [String: Job] = [:]
    /// L'app dont on montre les nouveautés (feuille par-dessus tout).
    @Published var changelog: AppEntry?
    @Published var selfRelease: Release?
    @Published var selfJob: Job?
    @Published var splashDone = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    var openMain: (() -> Void)?
    private var timer: Timer?
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
        await withTaskGroup(of: (String, Release?, Bool).self) { group in
            for e in entries {
                let repo = e.repo, asset = e.asset, id = e.id
                group.addTask {
                    do { return (id, try await GitHub.latest(repo: repo, asset: asset), true) }
                    catch { return (id, nil, false) }
                }
            }
            group.addTask {
                do { return ("__osahub", try await GitHub.latest(repo: Hub.selfRepo, asset: Hub.selfAsset), true) }
                catch { return ("__osahub", nil, false) }
            }
            for await (id, release, ok) in group {
                if !ok { failures += 1; continue }
                if id == "__osahub" {
                    selfRelease = release.flatMap { Version.isNewer($0.version, than: Hub.version) && $0.zip != nil ? $0 : nil }
                    continue
                }
                checked.insert(id)
                releases[id] = release
            }
        }
        offline = failures > entries.count / 2
        announce()
    }

    // MARK: Nouveautés

    private func seenKey(_ id: String) -> String { "vu.\(id)" }
    private func installedKey(_ id: String) -> String { "installe.\(id)" }
    private func notifiedKey(_ id: String) -> String { "notifie.\(id)" }

    /// Nouvelle version d'une app installée : on montre ses nouveautés (une fois par version),
    /// et une notification si OsaHUB est en arrière-plan.
    private func announce() {
        let fresh = updates.filter { defaults.string(forKey: seenKey($0.id)) != releases[$0.id]?.version }
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

    func install(_ e: AppEntry) {
        if case .downloading = jobs[e.id] { return }
        if jobs[e.id] == .installing { return }
        guard let zip = releases[e.id]?.zip else { return }
        jobs[e.id] = .downloading(0)
        let current = installed[e.id]?.url
        Task {
            do {
                let release = releases[e.id]?.version
                let target = try await Installer.install(e, from: zip, current: current, progress: { p in
                    Task { @MainActor in
                        if case .downloading = Hub.shared.jobs[e.id] { Hub.shared.jobs[e.id] = .downloading(p) }
                    }
                }, installing: {
                    Task { @MainActor in Hub.shared.jobs[e.id] = .installing }
                })
                if let release, let info = Hub.info(target) {
                    let plist = info["CFBundleShortVersionString"] as? String ?? "0"
                    defaults.set(["release": release, "plist": plist, "path": target.path], forKey: installedKey(e.id))
                }
                scanInstalled()
                jobs[e.id] = .done
                if let v = releases[e.id]?.version { defaults.set(v, forKey: seenKey(e.id)) }
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

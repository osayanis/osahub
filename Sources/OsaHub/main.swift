import AppKit

// `OsaHub icon <dossier>` : fabrique AppIcon.iconset (utilisé par build.sh).
let args = CommandLine.arguments
if args.count > 2, args[1] == "icon" {
    do {
        try MainActor.assumeIsolated { try IconArt.export(to: URL(fileURLWithPath: args[2])) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

// `OsaHub verifier` : télécharge la dernière release de chaque app et contrôle l'archive
// (identifiant, signature) comme avant une installation, sans rien installer.
if args.count > 1, args[1] == "verifier" {
    nonisolated(unsafe) var finished = false
    Task.detached {
        for e in Catalog.builtIn {
            do {
                guard let r = try await GitHub.latest(repo: e.repo, asset: e.asset), let zip = r.zip else {
                    print("\(e.name) : pas de release publiée"); continue
                }
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("OsaHub-verif-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: work) }
                let app = try await Installer.fetchApp(zip, into: work, bundleId: e.bundleId, name: e.name) { _ in }
                let v = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                print("\(e.name) \(r.version) : archive OK (app \(v)), \(r.images.count) image(s) dans les notes, notes \(r.notes.count) car.")
            } catch {
                print("\(e.name) : ÉCHEC \(error.localizedDescription)")
            }
        }
        finished = true
    }
    while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(0)
}

// `OsaHub essai <id> <dossier>` : installation complète dans <dossier> au lieu de /Applications.
if args.count > 3, args[1] == "essai", let e = Catalog.builtIn.first(where: { $0.id == args[2] }) {
    Installer.applications = args[3]
    nonisolated(unsafe) var finished = false
    Task.detached {
        do {
            guard let zip = try await GitHub.latest(repo: e.repo, asset: e.asset)?.zip else { print("pas de release"); exit(1) }
            let current = URL(fileURLWithPath: "\(args[3])/\(e.name).app")
            let has = FileManager.default.fileExists(atPath: current.path)
            let t = try await Installer.install(e, from: zip, current: has ? current : nil, progress: { _ in }, installing: { print("installation…") })
            print("installée dans \(t.path)")
        } catch { print("ÉCHEC \(error.localizedDescription)"); exit(1) }
        finished = true
    }
    while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(0)
}

OsaHubApp.main()

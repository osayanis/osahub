import AppKit

struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ s: String) { errorDescription = s }
}

enum Shell {
    /// Lance un outil et attend sa fin ; erreur si le code de sortie n'est pas 0.
    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw Failure(text.isEmpty ? "\(tool) a échoué." : text) }
        return text
    }
}

/// Téléchargement avec avancement.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private let dest: URL
    private let progress: (Double) -> Void
    private var cont: CheckedContinuation<URL, Error>?

    init(dest: URL, progress: @escaping (Double) -> Void) {
        self.dest = dest
        self.progress = progress
    }

    func run(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            cont = c
            let s = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            s.downloadTask(with: url).resume()
        }
    }

    private func finish(_ r: Result<URL, Error>) {
        cont?.resume(with: r)
        cont = nil
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
        if t > 0 { progress(Double(w) / Double(t)) }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { return finish(.failure(Failure("Téléchargement refusé (HTTP \(code))."))) }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: loc, to: dest)
            finish(.success(dest))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
        if let e { finish(.failure(e)) }
        s.finishTasksAndInvalidate()
    }
}

enum Installer {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    /// Dossier des apps (changé seulement par la commande d'essai, pour ne rien toucher).
    nonisolated(unsafe) static var applications = "/Applications"

    /// Télécharge l'archive, vérifie qu'elle contient bien l'app attendue (identifiant + signature
    /// intacte), quitte l'app si elle tourne, la remplace, puis la relance si elle tournait.
    static func install(_ e: AppEntry, from zip: URL, current: URL?,
                        progress: @escaping (Double) -> Void,
                        installing: @escaping () -> Void) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OsaHub-\(e.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let app = try await fetchApp(zip, into: work, bundleId: e.bundleId, name: e.name, progress: progress)
        installing()

        let target = destination(e, current: current)
        // En essai (autre dossier que /Applications), on ne touche jamais aux apps ouvertes.
        let wasRunning = applications == "/Applications" ? await quit(e.bundleId) : false
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: app)
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: app, to: target)
        }
        if wasRunning { await relaunch(target) }
        return target
    }

    /// Télécharge et décompresse l'archive, et rend l'app qu'elle contient, vérifiée.
    static func fetchApp(_ zip: URL, into work: URL, bundleId: String, name: String,
                         progress: @escaping (Double) -> Void) async throws -> URL {
        let archive = try await Downloader(dest: work.appendingPathComponent("app.zip"), progress: progress).run(zip)
        let out = work.appendingPathComponent("x")
        do { try Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, out.path]) }
        catch { throw Failure("L'archive de \(name) est illisible.") }
        guard let app = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw Failure("L'archive ne contient pas d'application.") }
        guard Bundle(url: app)?.bundleIdentifier == bundleId else {
            throw Failure("L'archive ne contient pas \(name) (identifiant inattendu).")
        }
        do { try Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) }
        catch { throw Failure("La signature de \(name) est abîmée : rien n'a été remplacé.") }
        return app
    }

    /// Une app déjà rangée dans Applications est remplacée sur place ; sinon (copie de
    /// développement ailleurs, ou première installation) elle va dans /Applications.
    static func destination(_ e: AppEntry, current: URL?) -> URL {
        if let c = current?.standardizedFileURL.path,
           c.hasPrefix(applications + "/") || c.hasPrefix(home.path + "/Applications/") {
            return URL(fileURLWithPath: c)
        }
        if FileManager.default.isWritableFile(atPath: applications) {
            return URL(fileURLWithPath: "\(applications)/\(e.name).app")
        }
        return home.appendingPathComponent("Applications/\(e.name).app")
    }

    /// Quitte l'app si elle tourne (5 s pour le faire proprement). Renvoie vrai si elle tournait.
    @MainActor
    static func quit(_ bundleId: String) async -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else { return false }
        apps.forEach { $0.terminate() }
        for _ in 0..<50 {
            if apps.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        apps.forEach { $0.forceTerminate() }
        try? await Task.sleep(for: .milliseconds(400))
        return true
    }

    @MainActor
    static func relaunch(_ url: URL) async {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// Mise à jour d'OsaHUB lui-même : un petit script attend qu'il se ferme, remplace l'app
    /// et la relance.
    @MainActor
    static func updateSelf(from zip: URL, progress: @escaping (Double) -> Void) async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("OsaHub-self-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let app = try await fetchApp(zip, into: work, bundleId: Bundle.main.bundleIdentifier ?? "com.osalabs.osahub",
                                     name: "OsaHUB", progress: progress)
        let current = Bundle.main.bundlePath
        let script = work.appendingPathComponent("remplacer.sh")
        try """
        #!/bin/bash
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(current)"
        /usr/bin/ditto "\(app.path)" "\(current)"
        rm -rf "\(work.path)"
        open "\(current)"
        """.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        try p.run()
        NSApp.terminate(nil)
    }
}

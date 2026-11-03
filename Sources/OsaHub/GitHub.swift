import Foundation

/// La dernière version publiée d'une app.
struct Release: Equatable {
    var version: String
    var title: String
    /// Notes de version (Markdown), sans les images.
    var notes: String
    var date: Date?
    var zip: URL?
    var page: URL
    /// Captures trouvées dans les notes ou jointes à la release.
    var images: [URL]
}

enum GitHub {
    private struct API: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let published_at: Date?
        let html_url: URL
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let content_type: String?
        }
    }

    /// nil : le dépôt n'a pas encore de release (ou n'existe pas encore).
    static func latest(repo: String, asset: String) async throws -> Release? {
        guard let data = try await get("https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        return parse(try decoder.decode(API.self, from: data), repo: repo, asset: asset)
    }

    /// GitHub sans compte : 60 requêtes par heure. Limite atteinte : on dit jusqu'à quand.
    struct RateLimited: Error { let until: Date? }

    /// Appel à l'API avec son ETag : une réponse « rien n'a changé » (304) ne compte pas dans
    /// la limite. La dernière réponse est gardée sur le disque et resservie si la limite est
    /// atteinte. nil : 404 (pas de release, ou dépôt pas encore créé).
    static func get(_ address: String) async throws -> Data? {
        let url = URL(string: address)!
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.osalabs.osahub/api", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = address.replacingOccurrences(of: "https://api.github.com/", with: "").map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let body = dir.appendingPathComponent(String(key) + ".json"), tag = dir.appendingPathComponent(String(key) + ".etag")
        let cached = try? Data(contentsOf: body)

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("OsaHUB", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        if cached != nil, let etag = try? String(contentsOf: tag, encoding: .utf8) { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200:
            try? data.write(to: body)
            if let etag = http?.value(forHTTPHeaderField: "ETag") { try? etag.write(to: tag, atomically: true, encoding: .utf8) }
            return data
        case 304 where cached != nil:
            return cached
        case 404:
            return nil
        case 403, 429:
            if let cached { RateLimit.hit(http); return cached }
            throw RateLimited(until: RateLimit.reset(http))
        default:
            throw URLError(.badServerResponse)
        }
    }

    enum RateLimit {
        nonisolated(unsafe) static var until: Date?
        static func reset(_ r: HTTPURLResponse?) -> Date? {
            (r?.value(forHTTPHeaderField: "x-ratelimit-reset")).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        }
        static func hit(_ r: HTTPURLResponse?) { until = reset(r) ?? Date().addingTimeInterval(3600) }
    }

    /// Les dernières versions publiées (pour l'historique et revenir à une ancienne version).
    static func history(repo: String, asset: String, count: Int = 15) async throws -> [Release] {
        guard let data = try await get("https://api.github.com/repos/\(repo)/releases?per_page=\(count)") else { return [] }
        return try decoder.decode([API].self, from: data).map { parse($0, repo: repo, asset: asset) }
    }

    private static var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    private static func parse(_ r: API, repo: String, asset: String) -> Release {
        let body = r.body ?? ""
        let (notes, inline) = extractImages(body, repo: repo)
        let attached = r.assets
            .filter { ($0.content_type ?? "").hasPrefix("image/") }
            .sorted { $0.name < $1.name }
            .map(\.browser_download_url)
        return Release(
            version: Version.clean(r.tag_name),
            title: r.name ?? r.tag_name,
            notes: notes,
            date: r.published_at,
            zip: r.assets.first { $0.name == asset }?.browser_download_url,
            page: r.html_url,
            images: unique(inline + attached))
    }

    /// Sort les images des notes (Markdown `![](…)` ou `<img src="…">`) et rend le texte sans elles.
    /// Les badges (shields.io) sont ignorés.
    static func extractImages(_ body: String, repo: String) -> (String, [URL]) {
        var images: [URL] = []
        var text = body
        let patterns = [#"!\[[^\]]*\]\(([^)\s]+)[^)]*\)"#, #"<img[^>]*?src=["']([^"']+)["'][^>]*>"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: m.range(at: 1))
                if let url = resolve(raw, repo: repo), !isBadge(url) { images.append(url) }
            }
            text = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
        }
        // Les liens nus vers des pièces jointes GitHub (glisser-déposer d'une image dans la release)
        if let re = try? NSRegularExpression(pattern: #"^\s*(https://github\.com/user-attachments/assets/[A-Za-z0-9-]+)\s*$"#, options: [.anchorsMatchLines]) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let url = URL(string: ns.substring(with: m.range(at: 1))) { images.append(url) }
            }
            text = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        let cleaned = text
            .replacingOccurrences(of: #"</?(p|div|picture|source)[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, images)
    }

    private static func resolve(_ raw: String, repo: String) -> URL? {
        if raw.hasPrefix("http") { return URL(string: raw) }
        let path = raw.hasPrefix("./") ? String(raw.dropFirst(2)) : raw
        return URL(string: "https://raw.githubusercontent.com/\(repo)/HEAD/\(path)")
    }

    private static func isBadge(_ url: URL) -> Bool {
        let s = url.absoluteString
        return s.contains("shields.io") || s.contains("/badge")
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}

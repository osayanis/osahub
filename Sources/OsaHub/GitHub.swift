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
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("OsaHUB", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw URLError(.badServerResponse) }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let r = try dec.decode(API.self, from: data)

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

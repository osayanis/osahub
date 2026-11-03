import Foundation

/// Une app de la suite, telle que le catalogue la décrit.
struct AppEntry: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var tagline: String
    var description: String
    /// Dépôt GitHub public dont la dernière release porte l'app (« osayanis/osaboot »).
    var repo: String
    var bundleId: String
    /// Archive de l'app dans la release (zippée avec ditto).
    var asset: String
    var accent: String
    /// Symbole affiché tant que l'icône n'est pas chargée (ou s'il n'y en a pas).
    var symbol: String
    var icon: URL?
    var screenshots: [URL]
}

enum Catalog {
    /// Le catalogue en ligne : ajouter une app ici suffit, sans republier OsaHUB.
    static let remote = URL(string: "https://raw.githubusercontent.com/osayanis/osahub/main/catalog.json")!

    static func asset(_ repo: String, _ file: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/\(repo)/HEAD/.github/assets/\(file)")!
    }

    /// Le catalogue embarqué, utilisé hors ligne ou si le catalogue en ligne est illisible.
    static let builtIn: [AppEntry] = [
        AppEntry(
            id: "osanotch", name: "OsaNotch",
            tagline: "Ton notch devient une Dynamic Island, avec une mascotte.",
            description: "Ta musique et ses paroles, tes fichiers, ton presse-papier, ton calendrier, OsaDrop et OsaCast, rangés dans l'encoche du Mac. Une petite mascotte y vit et réagit à ce qui se passe.",
            repo: "osayanis/osanotch-native", bundleId: "com.osalabs.osanotch", asset: "OsaNotch.zip",
            accent: "lilac", symbol: "rectangle.topthird.inset.filled",
            icon: asset("osayanis/osanotch-native", "icon.png"),
            screenshots: [asset("osayanis/osanotch-native", "banner.png")]),
        AppEntry(
            id: "osawallpaper", name: "OsaWallpaper",
            tagline: "Ton écran verrouillé prend les couleurs de ta musique.",
            description: "Des fonds d'écran animés et un écran verrouillé qui suit le morceau en cours. Les pastilles son et luminosité reprennent le style de la suite.",
            repo: "osayanis/osawallpaper", bundleId: "com.osalabs.osawallpaper", asset: "OsaWallpaper.zip",
            accent: "pink", symbol: "photo.stack",
            icon: asset("osayanis/osawallpaper", "icon.png"),
            screenshots: ["lockscreen.jpg", "gallery.jpg", "lockscreen-photo.jpg", "toast.png", "onboarding.png"]
                .map { asset("osayanis/osawallpaper", $0) }),
        AppEntry(
            id: "osaboot", name: "OsaBoot",
            tagline: "Flasher une clé USB, même avec une ISO Windows.",
            description: "Copie une image .iso ou .img sur une clé USB puis la vérifie. Prépare aussi une clé d'installation Windows 10 ou 11 depuis une ISO officielle.",
            repo: "osayanis/osaboot", bundleId: "com.osalabs.osaboot", asset: "OsaBoot.zip",
            accent: "mint", symbol: "externaldrive.fill",
            icon: asset("osayanis/osaboot", "icon.png"),
            screenshots: ["ready.png", "working.png", "done.png", "empty.png"].map { asset("osayanis/osaboot", $0) }),
        AppEntry(
            id: "osaweight", name: "OsaWeight",
            tagline: "Une balance de cuisine dans le trackpad.",
            description: "Les trackpads Force Touch ont des capteurs de force sous la dalle : OsaWeight les lit et affiche le poids de ce que tu poses dessus.",
            repo: "osayanis/osaweight", bundleId: "com.osalabs.osaweight", asset: "OsaWeight.zip",
            accent: "blue", symbol: "scalemass.fill",
            icon: nil, screenshots: []),
    ]

    static func fetchRemote() async -> [AppEntry]? {
        var req = URLRequest(url: remote)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode([AppEntry].self, from: data), !list.isEmpty
        else { return nil }
        return list
    }
}

enum Version {
    static func clean(_ tag: String) -> String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

    /// « 1.0.10 » est plus récent que « 1.0.9 » : comparaison nombre par nombre.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = clean(a).split(separator: ".").map { Int($0) ?? 0 }
        let pb = clean(b).split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

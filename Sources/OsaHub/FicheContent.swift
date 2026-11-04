import Foundation

/// Ce que la fiche raconte de chaque app, au-delà du catalogue : ses points forts, ce avec quoi
/// elle fonctionne, ce qu'il lui faut. Contenu statique, par identifiant du catalogue.
enum FicheContent {
    struct Feature: Hashable {
        let symbol: String
        let title: String
        let text: String
    }

    enum Target: Hashable {
        /// Une autre app du catalogue : le clic ouvre sa fiche.
        case app(String)
        /// Un site OsaLabs suivi par OsaHUB (Hub.serviceList) : le clic l'ouvre, son état s'affiche.
        case service(String)
        /// OsaHUB lui-même.
        case hub
        case web(name: String, url: URL, symbol: String)
    }

    struct Link: Hashable {
        let target: Target
        let text: String
    }

    struct Requirement: Hashable {
        let label: String
        let value: String
    }

    static func features(_ id: String) -> [Feature] {
        switch id {
        case "osanotch":
            return [
                Feature(symbol: "music.note", title: "Ta musique et ses paroles",
                        text: "Apple Music et Spotify : la pochette, les commandes, les paroles qui défilent ligne par ligne."),
                Feature(symbol: "face.smiling", title: "Une mascotte qui vit là",
                        text: "Elle suit ton curseur, danse avec ta musique et s'endort quand le notch se range."),
                Feature(symbol: "tray.full", title: "Tes fichiers sous la main",
                        text: "Glisse des fichiers sur l'encoche : ils t'attendent, même après un redémarrage."),
                Feature(symbol: "doc.on.clipboard", title: "Le presse-papier",
                        text: "Tes 20 derniers textes copiés. Les mots de passe ne sont jamais gardés."),
                Feature(symbol: "calendar", title: "Ta journée",
                        text: "Tes prochains événements, un miroir caméra et ta batterie, d'un coup d'œil."),
                Feature(symbol: "person.2", title: "Tes amis",
                        text: "Ajoute-les avec un code à 6 chiffres, puis partage ton écran ou écoute à plusieurs."),
            ]
        case "osawallpaper":
            return [
                Feature(symbol: "lock.fill", title: "L'écran verrouillé en musique",
                        text: "La pochette devient ton fond, avec l'heure, le lecteur et les paroles."),
                Feature(symbol: "play.rectangle", title: "Les pochettes animées",
                        text: "Quand l'artiste en a fait une, elle remplit tout ton écran, en vidéo."),
                Feature(symbol: "photo.on.rectangle", title: "Des milliers de fonds",
                        text: "Des photos en 4K, les vidéos aériennes d'Apple, ou ton propre lien."),
                Feature(symbol: "cloud.sun", title: "La météo",
                        text: "La température et le ciel sur l'écran verrouillé, sans compte."),
                Feature(symbol: "headphones", title: "Les pastilles",
                        text: "AirPods, charge, volume et luminosité, dans le style de la suite."),
                Feature(symbol: "display.2", title: "Sur tous tes écrans",
                        text: "Les écrans externes aussi. Tu déverrouilles : ton bureau reste comme avant."),
            ]
        case "osaboot":
            return [
                Feature(symbol: "externaldrive", title: "Glisse, branche, flashe",
                        text: "Une image .iso ou .img, ta clé USB, et c'est parti."),
                Feature(symbol: "checkmark.shield", title: "Vérifiée à la fin",
                        text: "La clé est relue et comparée à l'image, pour être sûr."),
                Feature(symbol: "pc", title: "Clés Windows 10 et 11",
                        text: "Depuis une ISO officielle. Les fichiers trop gros sont découpés tout seuls."),
                Feature(symbol: "lock.open", title: "Windows 11 sans TPM",
                        text: "En option, pour un PC sans TPM 2.0 ni Secure Boot."),
                Feature(symbol: "eraser", title: "EraseKEY",
                        text: "Une clé qui efface complètement le disque d'un PC."),
                Feature(symbol: "internaldrive", title: "Jamais le disque du Mac",
                        text: "Seuls les disques externes sont proposés."),
            ]
        case "osaweight":
            return [
                Feature(symbol: "hand.point.down", title: "Pose, c'est pesé",
                        text: "Un doigt sur le trackpad, pose l'objet : le poids s'affiche."),
                Feature(symbol: "scalemass", title: "Calibrée en une pesée",
                        text: "Un objet dont tu connais le poids, et la balance est prête."),
                Feature(symbol: "arrow.counterclockwise", title: "Retour à zéro",
                        text: "Pour peser ce qu'il y a dans le bol, sans le bol."),
                Feature(symbol: "rectangle.and.hand.point.up.left", title: "Rien à brancher",
                        text: "Les capteurs Force Touch sous la dalle font tout le travail."),
            ]
        default:
            return []
        }
    }

    static func links(_ id: String) -> [Link] {
        switch id {
        case "osanotch":
            return [
                Link(target: .app("osawallpaper"), text: "Ses pastilles son et luminosité prennent le relais, juste sous l'encoche."),
                Link(target: .service("osadrop"), text: "Envoie un fichier depuis le notch, avec un code."),
                Link(target: .service("osacast"), text: "Partage ton écran ou regarde celui d'un ami."),
                Link(target: .service("osaparty"), text: "Écoute à plusieurs : ton Mac sert de pont Apple Music."),
            ]
        case "osawallpaper":
            return [
                Link(target: .hub, text: "Ses options passent dans le menu d'OsaHUB : une seule mascotte dans la barre."),
                Link(target: .app("osanotch"), text: "Ses pastilles remplacent celles du notch et passent juste dessous."),
            ]
        case "osaboot":
            return [
                Link(target: .web(name: "EraseKEY", url: URL(string: "https://osalabs.fr/erasekey")!, symbol: "eraser"),
                     text: "Son site, pour tout savoir avant d'effacer un disque."),
                Link(target: .hub, text: "OsaHUB l'installe et la tient à jour."),
            ]
        case "osaweight":
            return [Link(target: .hub, text: "OsaHUB l'installera dès sa sortie.")]
        default:
            return [Link(target: .hub, text: "OsaHUB l'installe et la tient à jour.")]
        }
    }

    static func requirements(_ id: String) -> [Requirement] {
        var list = [Requirement(label: "Système", value: "macOS 14 ou plus"),
                    Requirement(label: "Processeur", value: "Apple Silicon")]
        if id == "osaweight" { list.append(Requirement(label: "Trackpad", value: "Force Touch")) }
        return list
    }
}

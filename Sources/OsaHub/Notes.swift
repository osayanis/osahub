import SwiftUI
import AppKit

/// Les notes de version, en Markdown simple : titres, listes, paragraphes, gras/italique/code/liens.
enum Notes {
    enum Block: Hashable {
        case heading(String, Int)
        case bullet(String)
        case paragraph(String)
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] }
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                out.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces), level))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                out.append(.bullet(String(line.dropFirst(2))))
            } else if line == "---" || line == "***" {
                flush()
            } else {
                para.append(line)
            }
        }
        flush()
        return out
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    /// Première ligne utile, sans Markdown (pour une notification).
    static func summary(_ text: String) -> String? {
        for b in blocks(text) {
            switch b {
            case .bullet(let s), .paragraph(let s):
                let plain = String(inline(s).characters)
                return plain.count > 160 ? String(plain.prefix(157)) + "…" : plain
            case .heading: continue
            }
        }
        return nil
    }
}

struct NotesView: View {
    let text: String
    var accent: Color = .white

    var body: some View {
        let blocks = Notes.blocks(text)
        VStack(alignment: .leading, spacing: 12) {
            if blocks.isEmpty {
                Text("Pas de notes pour cette version.").foregroundStyle(Theme.faint)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let s, let level):
                    Text(Notes.inline(s))
                        .font(.system(size: level <= 2 ? 15 : 13.5, weight: .bold))
                        .foregroundStyle(Theme.cream)
                        .padding(.top, 4)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Circle().fill(.white.opacity(0.4)).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(Notes.inline(s))
                    }
                case .paragraph(let s):
                    Text(Notes.inline(s))
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.75))
        .lineSpacing(3)
        .tint(accent)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Image distante, gardée en mémoire (et sur disque via URLCache) : pas de clignotement d'une vue à l'autre.
enum ImageStore {
    static let cache = NSCache<NSURL, NSImage>()
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var mode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: mode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        if let c = ImageStore.cache.object(forKey: url as NSURL) { image = c; return }
        image = nil
        guard let (d, r) = try? await URLSession.shared.data(from: url),
              (r as? HTTPURLResponse)?.statusCode == 200,
              let img = NSImage(data: d) else { return }
        ImageStore.cache.setObject(img, forKey: url as NSURL)
        withAnimation(.easeOut(duration: 0.3)) { image = img }
    }
}

/// L'icône d'une app : celle du dépôt, sinon une tuile à sa couleur avec son symbole.
struct AppIcon: View {
    let entry: AppEntry
    var size: CGFloat = 56

    var body: some View {
        RemoteImage(url: entry.icon, mode: .fit) {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.26), Color(red: 0.1, green: 0.1, blue: 0.14)], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: entry.symbol).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .padding(size * 0.04)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.12, y: size * 0.06)
    }
}

/// Défilement de captures : fondu flouté d'une capture à l'autre, flèches au survol, points dont
/// le remplissage montre l'avance automatique (toutes les 5 s, en pause au survol). Clic : plein cadre.
struct Carousel: View {
    let urls: [URL]
    var accent: Color = .white
    var symbol = "photo"
    var corner: CGFloat = 20
    /// Capture affichée, pilotée de l'extérieur (clavier, plein cadre) ; sinon gardée ici.
    var selection: Binding<Int>? = nil
    /// Clic sur la capture : l'ouvrir en grand.
    var onOpen: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var own = 0
    @State private var hover = false
    @State private var fill: CGFloat = 0

    private var index: Int {
        guard !urls.isEmpty else { return 0 }
        return min(max(0, selection?.wrappedValue ?? own), urls.count - 1)
    }

    var body: some View {
        ZStack {
            Theme.surface
            if urls.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 38, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
                    Text("Captures bientôt").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.35))
                }
            } else {
                ZStack {
                    ForEach(urls.indices, id: \.self) { i in
                        if i == index {
                            slide(urls[i])
                                .transition(.asymmetric(insertion: .ficheBlur(scale: reduce ? 1 : 1.015),
                                                        removal: .ficheBlur(scale: reduce ? 1 : 0.99)))
                        }
                    }
                }
                .animation(reduce ? .easeOut(duration: 0.2) : .easeOut(duration: 0.38), value: index)
                .contentShape(Rectangle())
                .onTapGesture { onOpen?(index) }
                if urls.count > 1 { controls }
                if onOpen != nil { expandHint }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Theme.line))
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
        .onChange(of: urls) { _, _ in set(0) }
        // L'avance automatique repart à chaque capture ; en pause au survol. Pas d'avance
        // automatique avec « Réduire les animations ».
        .task(id: "\(index)-\(hover)-\(urls.count)") {
            guard urls.count > 1, !reduce else { return }
            if hover { withAnimation(.easeOut(duration: 0.2)) { fill = 1 }; return }
            fill = 0
            withAnimation(.linear(duration: 5)) { fill = 1 }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { go(1) }
        }
    }

    private func set(_ i: Int) {
        if let selection { selection.wrappedValue = i } else { own = i }
    }

    private func slide(_ url: URL) -> some View {
        // Color.clear prend la taille proposée : l'image « remplie » ne peut pas agrandir le carrousel.
        Color.clear
            .overlay {
                // la même image, floutée, remplit les bords
                RemoteImage(url: url, mode: .fill) { Color.clear }
                    .blur(radius: 40).opacity(0.45)
            }
            .overlay {
                RemoteImage(url: url, mode: .fit) { ProgressView().controlSize(.small) }
                    .padding(14)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                    .scaleEffect(hover && onOpen != nil && !reduce ? 1.012 : 1)
                    .animation(.easeOut(duration: 0.3), value: hover)
            }
            .clipped()
    }

    private var expandHint: some View {
        VStack {
            HStack {
                Spacer()
                Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                    .opacity(hover ? 1 : 0)
                    .offset(y: hover || reduce ? 0 : -4)
            }
            Spacer()
        }
        .padding(14)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                ForEach(urls.indices, id: \.self) { i in
                    dot(i)
                        .contentShape(Rectangle().inset(by: -4))
                        .onTapGesture { set(i) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .leading) { arrow("chevron.left") { go(-1) } }
        .overlay(alignment: .trailing) { arrow("chevron.right") { go(1) } }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: index)
    }

    private func dot(_ i: Int) -> some View {
        let active = i == index
        return Capsule().fill(.white.opacity(active ? 0.3 : 0.28))
            .frame(width: active ? 22 : 6, height: 6)
            .overlay(alignment: .leading) {
                if active {
                    Capsule().fill(Theme.cream)
                        .frame(width: urls.count > 1 && !reduce ? max(6, 22 * fill) : 22)
                }
            }
    }

    private func arrow(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.cream)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
        }
        .buttonStyle(FichePress(scale: 0.92))
        .padding(.horizontal, 14)
        .opacity(hover ? 1 : 0)
        .offset(x: hover || reduce ? 0 : (name == "chevron.left" ? -6 : 6))
    }

    private func go(_ d: Int) {
        guard !urls.isEmpty else { return }
        set((index + d + urls.count) % urls.count)
    }
}

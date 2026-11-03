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

/// Défilement de captures : flèches au survol, points, avance seule toutes les 5 s.
struct Carousel: View {
    let urls: [URL]
    var accent: Color = .white
    var symbol = "photo"
    var corner: CGFloat = 20

    @State private var index = 0
    @State private var forward = true
    @State private var hover = false

    var body: some View {
        ZStack {
            Theme.surface
            if urls.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 38, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
                    Text("Captures bientôt").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.35))
                }
            } else {
                ForEach(urls.indices, id: \.self) { i in
                    if i == index { slide(urls[i]).transition(slideTransition) }
                }
                if urls.count > 1 { controls }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Theme.line))
        .onHover { hover = $0 }
        .task(id: urls) {
            index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !hover, urls.count > 1 { go(1) }
            }
        }
    }

    private var slideTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
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
            }
            .clipped()
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                ForEach(urls.indices, id: \.self) { i in
                    Capsule().fill(i == index ? Theme.cream : .white.opacity(0.3))
                        .frame(width: i == index ? 18 : 6, height: 6)
                        .onTapGesture { forward = i > index; withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { index = i } }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .leading) { arrow("chevron.left") { go(-1) } }
        .overlay(alignment: .trailing) { arrow("chevron.right") { go(1) } }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
    }

    private func arrow(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.cream)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .opacity(hover ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: hover)
    }

    private func go(_ d: Int) {
        forward = d > 0
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            index = (index + d + urls.count) % urls.count
        }
    }
}

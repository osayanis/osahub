import SwiftUI

// L'identité animée d'OsaHUB.
//
// Le logo : quatre tuiles (les apps de la suite), celle du bas à droite porte une flèche de
// téléchargement, à côté du mot « OsaHUB ». À l'ouverture, une poussière de points converge vers
// le centre, s'allume, les tuiles se déplient depuis ce point, la flèche tombe dans sa tuile, le
// logo glisse pour laisser monter les lettres, un reflet traverse le tout, puis le logo s'envole
// se ranger en haut à gauche de la fenêtre, où il reste vivant (il ondule quand OsaHUB travaille).
// Tout est calculé à partir du temps écoulé : chaque image est exacte, rien ne dérive.
// Noir et blanc seulement, comme OsaWallpaper.

enum Ease {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    /// Avancement de 0 à 1 entre `start` et `start + duration`.
    static func progress(_ t: Double, _ start: Double, _ duration: Double) -> Double { clamp((t - start) / duration) }
    static func outCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inCubic(_ x: Double) -> Double { x * x * x }
    static func inOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func outExpo(_ x: Double) -> Double { x >= 1 ? 1 : 1 - pow(2, -10 * x) }
    /// Ressort amorti : dépasse un peu 1 puis s'y pose.
    static func spring(_ x: Double, bounce: Double = 0.32) -> Double {
        guard x < 1 else { return 1 }
        return 1 - exp(-6.5 * x) * cos(x * .pi * (2.2 + bounce * 4)) * (1 - x * 0.2)
    }
    /// Une bosse : 0 → 1 → 0 sur `duration`.
    static func bump(_ t: Double, _ start: Double, _ duration: Double) -> Double {
        let p = progress(t, start, duration)
        return p <= 0 || p >= 1 ? 0 : sin(p * .pi)
    }
}

/// Les quatre tuiles.
struct HubMark: View {
    var size: CGFloat
    /// Apparition de chaque tuile (0 → 1, peut dépasser 1 : ressort).
    var appear: [Double] = [1, 1, 1, 1]
    /// Éclat en plus de chaque tuile (0 → 1).
    var glow: [Double] = [0, 0, 0, 0]
    /// Chute de la flèche dans sa tuile (0 → 1).
    var arrow: Double = 1
    /// Écart supplémentaire entre les tuiles (survol).
    var spread: CGFloat = 0

    private static let base: [Double] = [0.95, 0.42, 0.42, 0.95]

    var body: some View {
        let gap = size * 0.12 + spread
        let tile = (size - size * 0.12) / 2
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let col = CGFloat(i % 2) * 2 - 1, row = CGFloat(i / 2) * 2 - 1
                let a = appear[i]
                let home = CGSize(width: col * (tile + gap) / 2, height: row * (tile + gap) / 2)
                let k = CGFloat(min(1, max(0, a)))
                RoundedRectangle(cornerRadius: tile * 0.3, style: .continuous)
                    .fill(Color.white.opacity(min(1, Self.base[i] + glow[i] * 0.5)))
                    .overlay {
                        if i == 3 { arrowShape(tile) }
                    }
                    .frame(width: tile, height: tile)
                    .shadow(color: .white.opacity(glow[i] * 0.55), radius: tile * 0.45 * glow[i])
                    .scaleEffect(max(0.001, a))
                    .rotationEffect(.degrees((1 - Double(k)) * 90 * Double(col * row)))
                    // les tuiles partent du centre et se déplient vers leur coin
                    .offset(x: home.width * (0.15 + 0.85 * k), y: home.height * (0.15 + 0.85 * k))
                    .opacity(Double(k))
            }
        }
        .frame(width: size + spread, height: size + spread)
    }

    private func arrowShape(_ tile: CGFloat) -> some View {
        Image(systemName: "arrow.down")
            .font(.system(size: tile * 0.5, weight: .heavy))
            .foregroundStyle(Color.black.opacity(0.88))
            .offset(y: -tile * 0.55 * (1 - arrow))
            .opacity(arrow)
            .mask(RoundedRectangle(cornerRadius: tile * 0.3, style: .continuous).frame(width: tile, height: tile))
    }
}

/// Le logo complet (tuiles + mot), dessiné pour un instant `t` de l'animation d'ouverture.
/// Après 3 s, c'est le logo au repos.
struct Lockup: View {
    var size: CGFloat = 72
    var t: Double = 10
    var glow: [Double] = [0, 0, 0, 0]
    var spread: CGFloat = 0
    /// Largeur du mot, mesurée (pour centrer les tuiles seules au début).
    @State private var wordWidth: CGFloat = 0

    static let letters = Array("OsaHUB")

    var body: some View {
        let spacing = size * 0.3
        let slide = Ease.inOutCubic(Ease.progress(t, 1.2, 0.6))
        HStack(spacing: spacing) {
            HubMark(size: size * 0.86,
                    appear: (0..<4).map { Ease.spring(Ease.progress(t, 0.62 + Double($0) * 0.07, 0.75)) },
                    glow: (0..<4).map { min(1, glow[$0] + Ease.bump(t, 2.1 + Double($0) * 0.09, 0.5) * 0.9 + Ease.bump(t, 0.6, 0.35)) },
                    arrow: Ease.spring(Ease.progress(t, 1.0, 0.55), bounce: 0.15),
                    spread: spread)
            word
                .background(GeometryReader { g in Color.clear.onAppear { wordWidth = g.size.width } })
        }
        // au début, les tuiles seules sont au centre ; le logo glisse pour faire place au mot
        .offset(x: (1 - slide) * (wordWidth + spacing) / 2)
    }

    private var word: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.letters.enumerated()), id: \.offset) { i, ch in
                let p = Ease.progress(t, 1.38 + Double(i) * 0.055, 0.7)
                let s = Ease.spring(p, bounce: 0.2)
                Text(String(ch))
                    .foregroundStyle(i < 3 ? AnyShapeStyle(Theme.cream) : AnyShapeStyle(Theme.hubGradient))
                    .offset(y: (1 - s) * size * 0.95)
                    .rotationEffect(.degrees((1 - min(1, s)) * 14), anchor: .bottomLeading)
                    .blur(radius: (1 - Ease.outCubic(p)) * 5)
                    .opacity(Ease.outCubic(p))
            }
        }
        .font(.system(size: size, weight: .bold))
        .kerning(-size * 0.025)
        // les lettres sortent d'une fente : on ne les voit pas sous la ligne de base
        .mask(Rectangle().padding(.top, -size).padding(.horizontal, -size * 0.2))
        .overlay { shine.mask(word0) }
    }

    /// Le mot au repos, pour masquer le reflet.
    private var word0: some View {
        HStack(spacing: 0) { Text("Osa"); Text("HUB") }
            .font(.system(size: size, weight: .bold))
            .kerning(-size * 0.025)
    }

    private var shine: some View {
        GeometryReader { g in
            let p = Ease.inOutCubic(Ease.progress(t, 2.0, 0.85))
            LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.35)
                .rotationEffect(.degrees(18))
                .offset(x: -g.size.width * 0.5 + p * g.size.width * 1.6)
                .opacity(p > 0 && p < 1 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

/// Ce qui entoure le logo pendant l'ouverture : la poussière qui converge, l'éclair, les anneaux,
/// la devise. Disparaît quand le logo s'envole.
struct SplashScenery: View {
    let t: Double

    private struct Dust { let angle, radius, delay, size: Double }
    private static let dust: [Dust] = (0..<90).map { i in
        var g = SeededRandom(seed: UInt64(i) &* 2654435761 &+ 12345)
        return Dust(angle: g.next() * .pi * 2, radius: 260 + g.next() * 520, delay: g.next() * 0.28, size: 1 + g.next() * 2.2)
    }

    var body: some View {
        ZStack {
            // lueur derrière le logo
            Ellipse().fill(.white).frame(width: 760, height: 320).blur(radius: 150)
                .opacity(0.02 + 0.06 * Ease.outCubic(Ease.progress(t, 0.55, 0.9)))
            // la poussière : chaque point file vers le centre et s'éteint en arrivant
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                for d in Self.dust {
                    let p = Ease.progress(t, d.delay, 0.62)
                    guard p < 1 else { continue }
                    let r = d.radius * (1 - Ease.inCubic(p))
                    let a = d.angle + p * 0.9
                    let x = c.x + cos(a) * r, y = c.y + sin(a) * r * 0.62
                    let o = min(1, p * 5) * (1 - p) * 0.9
                    ctx.fill(Path(ellipseIn: CGRect(x: x - d.size / 2, y: y - d.size / 2, width: d.size, height: d.size)),
                             with: .color(.white.opacity(o)))
                }
            }
            // l'éclair au moment où tout se rejoint, puis deux ondes
            Circle().fill(.white).frame(width: 14, height: 14).blur(radius: 4)
                .scaleEffect(0.2 + Ease.bump(t, 0.5, 0.3) * 2.4)
                .opacity(Ease.bump(t, 0.5, 0.3))
            ForEach([0.0, 0.12], id: \.self) { d in
                let p = Ease.outExpo(Ease.progress(t, 0.6 + d, 1.1))
                Circle().strokeBorder(.white.opacity(0.35 * (1 - p)), lineWidth: 1)
                    .frame(width: 20 + p * 820, height: 20 + p * 820)
                    .opacity(p > 0 ? 1 : 0)
            }
            // la devise, sous le logo
            VStack(spacing: 18) {
                Spacer().frame(height: 150)
                Capsule().fill(.white.opacity(0.22))
                    .frame(width: 260 * Ease.inOutCubic(Ease.progress(t, 2.1, 0.6)), height: 1.5)
                Text("TOUTES LES APPS OSALABS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(3.2 + 9 * (1 - Ease.outCubic(Ease.progress(t, 2.2, 0.8))))
                    .foregroundStyle(.white.opacity(0.42))
                    .opacity(Ease.outCubic(Ease.progress(t, 2.2, 0.6)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Petit générateur pseudo-aléatoire à graine fixe : la poussière est la même à chaque ouverture.
struct SeededRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Double(s % 1_000_000) / 1_000_000
    }
}

/// Le logo vivant, qui fait l'ouverture puis se range en haut à gauche. Posé par-dessus toute
/// la fenêtre (RootView) ; la barre du haut lui laisse sa place.
struct LivingLogo: View {
    @EnvironmentObject private var hub: Hub
    /// Le logo est rangé dans la barre du haut.
    let docked: Bool
    let finish: () -> Void
    let tap: () -> Void

    @State private var start = Date()
    @State private var finished = false
    @State private var glow: [Double] = [0, 0, 0, 0]
    @State private var hover = false
    @State private var size: CGSize = .zero

    static let splashSize: CGFloat = 72
    static let dockedSize: CGFloat = 22
    static let dockedLeading: CGFloat = 36
    static let dockedY: CGFloat = 50
    static let duration = 3.15

    var body: some View {
        GeometryReader { g in
            let scale = docked ? Self.dockedSize / Self.splashSize : 1
            ZStack {
                if !docked {
                    TimelineView(.animation(paused: docked)) { tl in
                        let t = tl.date.timeIntervalSince(start)
                        ZStack {
                            SplashScenery(t: t)
                            Lockup(size: Self.splashSize, t: t)
                                .fixedSize()
                                .background(GeometryReader { lg in Color.clear.onAppear { size = lg.size } })
                                // c'est la copie rangée qui s'envole : celle-ci disparaît d'un coup
                                .opacity(finished ? 0 : 1)
                                .transaction { $0.animation = nil }
                                .position(x: g.size.width / 2, y: g.size.height / 2)
                        }
                        .onChange(of: t >= Self.duration) { _, done in if done { end() } }
                    }
                    .transition(.opacity)
                } else {
                    Lockup(size: Self.splashSize, t: 10, glow: glow, spread: hover ? 10 : 0)
                        .fixedSize()
                        .background(GeometryReader { lg in Color.clear.onAppear { size = lg.size } })
                        .scaleEffect(scale)
                        .position(x: Self.dockedLeading + size.width * scale / 2, y: Self.dockedY)
                        .onTapGesture(perform: tap)
                        .onHover { h in withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { hover = h } }
                        .help("Toutes les apps")
                        .transition(.asymmetric(insertion: .modifier(active: Fly(amount: 1, window: g.size, scale: scale, logo: size), identity: Fly(amount: 0, window: g.size, scale: scale, logo: size)),
                                                removal: .opacity))
                }
            }
            .contentShape(Rectangle().size(docked ? .zero : g.size))
            .onTapGesture { if !docked { end() } }
        }
        .ignoresSafeArea()
        .task(id: busy) { await alive() }
    }

    private var busy: Bool { hub.checking || !hub.jobs.isEmpty }

    private func end() {
        guard !finished else { return }
        finished = true
        finish()
    }

    /// Au repos, une onde traverse les tuiles de temps en temps ; quand OsaHUB travaille
    /// (vérification, téléchargement), elle tourne en boucle.
    private func alive() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(busy ? 1.1 : 9))
            guard docked, !Task.isCancelled else { continue }
            for i in [0, 1, 3, 2] {
                withAnimation(.easeOut(duration: 0.22)) { glow[i] = 1 }
                try? await Task.sleep(for: .milliseconds(110))
                let k = i
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.easeIn(duration: 0.5)) { glow[k] = 0 }
                }
            }
        }
    }
}

/// L'envol du logo : du centre de la fenêtre (taille d'ouverture) à sa place dans la barre.
/// Même structure dans les deux états (sinon SwiftUI remplace la vue au lieu de l'animer).
private struct Fly: ViewModifier {
    /// 1 : encore au centre, 0 : arrivé.
    let amount: CGFloat
    let window: CGSize
    let scale: CGFloat
    let logo: CGSize
    func body(content: Content) -> some View {
        let dockedX = LivingLogo.dockedLeading + logo.width * scale / 2
        let k = 1 + (1 / scale - 1) * amount
        content
            .scaleEffect(k, anchor: UnitPoint(x: dockedX / max(1, window.width), y: LivingLogo.dockedY / max(1, window.height)))
            .offset(x: (window.width / 2 - dockedX) * amount, y: (window.height / 2 - LivingLogo.dockedY) * amount)
    }
}

import SwiftUI
import AppKit

struct StatusLine: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.faint)
    }

    private var color: Color {
        if case .failed = hub.jobs[entry.id] { return Theme.red }
        if hub.hasUpdate(entry) { return Theme.accent(entry.accent) }
        if hub.installed[entry.id] != nil { return Theme.ok }
        return .white.opacity(0.25)
    }

    private var text: String {
        if case .failed(let m) = hub.jobs[entry.id] { return m }
        let latest = hub.releases[entry.id]?.version
        if let i = hub.installed[entry.id] {
            if hub.hasUpdate(entry), let latest { return "v\(i.version) installée · v\(latest) disponible" }
            return "Installée · v\(i.version)"
        }
        if let latest, hub.releases[entry.id]?.zip != nil { return "Pas installée · v\(latest)" }
        if hub.isComingSoon(entry) { return "Pas encore publiée" }
        if let until = hub.limitedUntil { return "GitHub en pause jusqu'à \(until.formatted(date: .omitted, time: .shortened))" }
        if hub.offline { return "Hors ligne" }
        return "Recherche de la dernière version…"
    }
}


/// Installer / Mettre à jour / Ouvrir, avec l'avancement. Chaque état arrive en fondu flouté ;
/// la fin d'une installation dessine une coche.
struct ActionButton: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    var large = false

    var body: some View {
        let accent = Theme.accent(entry.accent)
        ZStack {
            switch hub.jobs[entry.id] {
            case .downloading(let p)?:
                ProgressPill(progress: p, label: "\(Int(p * 100)) %", accent: accent, large: large)
            case .installing?:
                ProgressPill(progress: nil, label: "Installation…", accent: accent, large: large)
            case .done?:
                HStack(spacing: 7) {
                    FicheCheck(size: large ? 17 : 14)
                    Text("Installée")
                }
                .font(.system(size: large ? 14 : 12.5, weight: .semibold))
                .foregroundStyle(Theme.ok)
                .padding(.horizontal, large ? 22 : 14).padding(.vertical, large ? 10 : 7)
                .background(Theme.surfaceHi, in: Capsule())
            case .failed?:
                Button { hub.install(entry) } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
                    .buttonStyle(PillStyle(fill: Theme.red.opacity(0.9), large: large))
            case nil:
                if hub.hasUpdate(entry) {
                    Button { hub.install(entry) } label: { Label("Mettre à jour", systemImage: "arrow.down") }
                        .buttonStyle(PillStyle(large: large))
                } else if hub.installed[entry.id] != nil {
                    Button("Ouvrir") { hub.open(entry) }
                        .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream, large: large))
                } else if hub.releases[entry.id]?.zip != nil {
                    Button { hub.install(entry) } label: { Label("Installer", systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(PillStyle(large: large))
                } else if hub.isComingSoon(entry) {
                    Text("Bientôt")
                        .font(.system(size: large ? 14 : 12.5, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .padding(.horizontal, large ? 22 : 14).padding(.vertical, large ? 11 : 7)
                        .background(Theme.surface, in: Capsule())
                } else if hub.limitedUntil != nil || hub.offline {
                    EmptyView()
                } else {
                    ProgressView().controlSize(.small).frame(width: 60)
                }
            }
        }
        .id(phase)
        .transition(.ficheBlur(scale: 0.96))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hub.jobs[entry.id])
    }

    /// Un nom par état (le pourcentage n'en change pas) : la transition ne joue qu'au changement d'état.
    private var phase: String {
        switch hub.jobs[entry.id] {
        case .downloading?: return "dl"
        case .installing?: return "inst"
        case .done?: return "ok"
        case .failed?: return "err"
        case nil: return hub.hasUpdate(entry) ? "maj" : hub.installed[entry.id] != nil ? "ouvrir" : "rien"
        }
    }
}

/// L'avancement : la barre se remplit avec un ressort, un reflet la traverse tant que ça travaille,
/// le pourcentage roule.
struct ProgressPill: View {
    let progress: Double?
    let label: String
    let accent: Color
    var large = false

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.surfaceHi)
            if let progress {
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.24))
                        .overlay(FicheSheen().clipShape(Capsule()))
                        .frame(width: max(g.size.height, g.size.width * progress))
                        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: progress)
                }
            } else {
                Capsule().fill(.white.opacity(0.1)).overlay(FicheSheen())
            }
            HStack(spacing: 6) {
                if progress == nil { ProgressView().controlSize(.mini).tint(Theme.cream) }
                Text(label).monospacedDigit()
                    .contentTransition(.numericText(value: progress ?? 0))
            }
            .font(.system(size: large ? 14 : 12.5, weight: .semibold))
            .foregroundStyle(Theme.cream)
            .frame(maxWidth: .infinity)
        }
        .frame(width: large ? 170 : 128, height: large ? 42 : 31)
        .clipShape(Capsule())
    }
}

// MARK: - Fiche d'une app

/// La fiche : en-tête (icône en parallaxe), captures (plein cadre au clic, ← →), ce qu'elle fait,
/// avec quoi elle fonctionne, nouveautés, infos, versions. Les liens vers une autre app de la suite
/// ouvrent sa fiche ici même ; le bouton retour (ou Échap) revient en arrière.
struct DetailView: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.accessibilityReduceMotion) private var reduce
    let entry: AppEntry
    let back: () -> Void

    /// Fiches ouvertes depuis « Fonctionne avec », la dernière est affichée.
    @State private var trail: [AppEntry] = []
    @State private var shot = 0
    @State private var viewer = false
    @State private var compact = false
    @State private var scroll = FicheScroll()
    /// Captures uniquement (OSAHUB_CHANGELOG) : la feuille des nouveautés ouverte d'ici.
    @State private var testSheet: AppEntry?

    private var current: AppEntry { trail.last ?? entry }

    var body: some View {
        let app = current
        let release = hub.releases[app.id]
        let shots = gallery(app, release)
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    // « haut » : le tout début du contenu (au-dessus de la marge), pas le bouton retour,
                    // sinon remonter laissait le bouton caché sous la barre du haut
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("haut")
                        VStack(alignment: .leading, spacing: 0) {
                            backButton
                                .padding(.bottom, 30)
                            // ZStack : l'ancienne fiche et la nouvelle se superposent pendant le fondu
                            // (empilées, elles doublaient la hauteur et décalaient le défilement)
                            ZStack(alignment: .top) {
                                sections(app, release, shots)
                                    .id(app.id)
                                    .transition(.ficheBlur(y: 12))
                            }
                            Color.clear.frame(height: 1).id("bas")
                        }
                        .padding(.horizontal, 36)
                        .padding(.top, 96)
                        .padding(.bottom, 110)
                        .frame(maxWidth: 1000)
                        .frame(maxWidth: .infinity)
                        // (une préférence lue par onPreferenceChange ne suit pas le défilement sur macOS)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("fiche")).minY } action: { track($0) }
                    }
                }
                .coordinateSpace(name: "fiche")
                .scrollIndicators(.never)

                if compact && !viewer {
                    FicheDock(entry: app) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { proxy.scrollTo("haut", anchor: .top) }
                    }
                    .padding(.bottom, 20)
                    .transition(reduce ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }

                if viewer {
                    FicheViewer(urls: shots, index: $shot) { closeViewer() }
                        .transition(.opacity)
                        .zIndex(5)
                }
            }
            .background { keyboard(count: shots.count) }
            .onAppear { testHooks(proxy) }
            .onChange(of: entry.id) { _, _ in trail = []; shot = 0; viewer = false }
            .onChange(of: app.id) { _, _ in
                hub.loadHistory(current)
                shot = 0
                proxy.scrollTo("haut", anchor: .top)
                // et encore une fois le fondu terminé, si la hauteur a changé entre-temps
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("haut", anchor: .top) }
            }
        }
        .onAppear { hub.loadHistory(app) }
        .sheet(item: $testSheet) { e in ChangelogSheet(entry: e).environmentObject(hub) }
    }

    @ViewBuilder
    private func sections(_ app: AppEntry, _ release: Release?, _ shots: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 40) {
            FicheHero(entry: app, scroll: scroll)

            Carousel(urls: shots, accent: Theme.accent(app.accent), symbol: app.symbol,
                     selection: $shot, onOpen: { i in openViewer(i) })
                .frame(height: 430)
                .ficheReveal(3)

            VStack(alignment: .leading, spacing: 30) {
                Text(app.description)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(4)
                    .frame(maxWidth: 660, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                FicheFeatures(entry: app, soon: release?.zip == nil && hub.isComingSoon(app))
            }
            .id("points")
            .ficheReveal(4)

            FicheLinks(entry: app) { openLinked($0) }
                .id("liens")
                .ficheReveal(5)

            if let release {
                FicheReleaseCard(release: release).ficheReveal(6)
            }

            FicheInfos(entry: app)
                .id("infos")
                .ficheReveal(7)

            VersionHistory(entry: app)
        }
    }

    private var backButton: some View {
        Button(action: escape) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                Text(backLabel).contentTransition(.opacity)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(FichePress())
        .keyboardShortcut(hub.palette ? nil : KeyboardShortcut(.escape, modifiers: []))
        .help("Revenir (Échap)")
    }

    private var backLabel: String {
        switch trail.count {
        case 0: return "Toutes les apps"
        case 1: return entry.name
        default: return trail[trail.count - 2].name
        }
    }

    /// ← → font défiler les captures (dans la fiche comme en plein cadre). Pas quand la recherche
    /// rapide est ouverte : ses touches sont à elle.
    @ViewBuilder private func keyboard(count: Int) -> some View {
        if !hub.palette && count > 1 {
            ZStack {
                Button("Capture précédente") { step(-1, count) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Capture suivante") { step(1, count) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private func step(_ d: Int, _ count: Int) {
        shot = ((min(shot, count - 1) + d) % count + count) % count
    }

    /// Échap : ferme le plein cadre, sinon revient à la fiche précédente, sinon à l'accueil.
    private func escape() {
        if viewer { closeViewer(); return }
        if !trail.isEmpty {
            withAnimation(FicheMotion.enter(reduce)) { _ = trail.removeLast() }
            return
        }
        back()
    }

    private func openLinked(_ e: AppEntry) {
        guard e.id != current.id else { return }
        withAnimation(FicheMotion.enter(reduce)) {
            if let i = trail.firstIndex(where: { $0.id == e.id }) {
                trail.removeSubrange((i + 1)...)
            } else if e.id == entry.id {
                trail = []
            } else {
                trail.append(e)
            }
        }
    }

    private func openViewer(_ i: Int) {
        shot = i
        withAnimation(.easeOut(duration: reduce ? 0.18 : 0.25)) { viewer = true }
    }

    private func closeViewer() {
        withAnimation(.easeOut(duration: 0.18)) { viewer = false }
    }

    private func track(_ y: CGFloat) {
        scroll.y = y
        if scroll.rest == nil { scroll.rest = y }
        let c = scroll.scrolled > 200
        if c != compact { withAnimation(FicheMotion.state(reduce)) { compact = c } }
    }

    private func gallery(_ app: AppEntry, _ r: Release?) -> [URL] {
        var seen = Set<URL>()
        return ((r?.images ?? []) + app.screenshots).filter { seen.insert($0).inserted }
    }

    /// Variables d'environnement des captures (instance de test) : rien n'est installé ni enregistré.
    ///   OSAHUB_FICHE_SCROLL=points|liens|infos|bas   descend dans la fiche
    ///   OSAHUB_VIEWER=<n>                     ouvre la capture n en plein cadre
    ///   OSAHUB_CHANGELOG=<id>                 ouvre la feuille des nouveautés de cette app
    ///   OSAHUB_FICHE_LIEN=<id>                suit le lien « Fonctionne avec » vers cette app
    ///   OSAHUB_DEMO_JOB=0.42|installation|fini  montre un avancement (en mémoire seulement)
    private func testHooks(_ proxy: ScrollViewProxy) {
        let env = ProcessInfo.processInfo.environment
        if let id = env["OSAHUB_FICHE_LIEN"], let e = hub.entries.first(where: { $0.id == id }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { openLinked(e) }
        }
        if let where_ = env["OSAHUB_FICHE_SCROLL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                proxy.scrollTo(where_, anchor: where_ == "bas" ? .bottom : .top)
            }
        }
        if let n = env["OSAHUB_VIEWER"].flatMap(Int.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { openViewer(n) }
        }
        if let id = env["OSAHUB_CHANGELOG"], let e = hub.entries.first(where: { $0.id == id }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { testSheet = e }
        }
        if let job = env["OSAHUB_DEMO_JOB"] {
            let id = env["OSAHUB_FICHE_LIEN"] ?? env["OSAHUB_CHANGELOG"] ?? current.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                switch job {
                case "installation": hub.jobs[id] = .installing
                case "fini": hub.jobs[id] = .done
                default: hub.jobs[id] = .downloading(Double(job) ?? 0.42)
                }
            }
        }
    }
}

// MARK: - Historique des versions

/// Les versions précédentes en frise : un point par version (vert pour celle installée),
/// les notes se déplient sous la ligne.
struct VersionHistory: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.accessibilityReduceMotion) private var reduce
    let entry: AppEntry
    @State private var open: String?
    @State private var all = false
    private let first = 5

    var body: some View {
        let list = (hub.history[entry.id] ?? []).filter { $0.version != hub.releases[entry.id]?.version }
        if !list.isEmpty {
            let visible = all ? list : Array(list.prefix(first))
            VStack(alignment: .leading, spacing: 14) {
                FicheSectionTitle(title: "Versions précédentes", detail: "pour revenir en arrière si une mise à jour te gêne")
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.version) { i, r in
                        FicheHistoryRow(entry: entry, release: r, expanded: open == r.version,
                                        lineAbove: i > 0, lineBelow: i < visible.count - 1 || list.count > visible.count) {
                            withAnimation(FicheMotion.state(reduce)) { open = open == r.version ? nil : r.version }
                        }
                        .modifier(FicheRowIn(index: i))
                    }
                }

                if list.count > first {
                    Button {
                        withAnimation(FicheMotion.state(reduce)) { all.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(all ? "Voir moins" : "Voir les \(list.count - first) autres")
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                                .rotationEffect(.degrees(all ? 180 : 0))
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.leading, 40)
                    }
                    .buttonStyle(FichePress())
                }
            }
            .transition(.opacity)
        }
    }
}

/// Le fil de la frise dans une ligne : au-dessus et/ou au-dessous du point.
private struct FicheRailLine: Shape {
    let above: Bool
    let below: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        let x = FicheHistoryRow.dotX, y = FicheHistoryRow.dotY
        if above { p.addRect(CGRect(x: x - 0.5, y: r.minY, width: 1, height: y - 7)) }
        if below { p.addRect(CGRect(x: x - 0.5, y: y + 7, width: 1, height: max(0, r.maxY - y - 7))) }
        return p
    }
}

private struct FicheRowIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 8)
            .onAppear { withAnimation(FicheMotion.enter(reduce, delay: Double(min(index, 8)) * 0.04)) { shown = true } }
    }
}

private struct FicheHistoryRow: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    let release: Release
    let expanded: Bool
    let lineAbove: Bool
    let lineBelow: Bool
    /// Centre du point dans la ligne.
    static let dotX: CGFloat = 11
    static let dotY: CGFloat = 26.5
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        let current = hub.installed[entry.id]?.version == release.version
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FicheVersionChip(version: release.version)
                Text(Notes.summary(release.notes) ?? release.title)
                    .font(.system(size: 12.5)).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer(minLength: 8)
                if let d = release.date {
                    Text(d.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.faint)
                }
                if current {
                    Text("installée").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ok)
                } else if release.zip != nil && hub.jobs[entry.id] == nil {
                    // au survol seulement : la liste reste calme
                    Button("Installer") { hub.install(entry, version: release) }
                        .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
                        .help("Remplace la version installée par la \(release.version)")
                        .opacity(hover || expanded ? 1 : 0)
                        .allowsHitTesting(hover || expanded)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.faint)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .frame(minHeight: 31)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            if expanded {
                NotesView(text: release.notes, accent: Theme.cream)
                    .padding(.bottom, 4)
                    .transition(.ficheBlur(y: -6))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background((hover || expanded) ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.leading, 28)
        .background(alignment: .topLeading) { rail(current) }
        .background { FicheRailLine(above: lineAbove, below: lineBelow).fill(Theme.line) }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }

    /// Le point de la version sur le fil.
    private func rail(_ current: Bool) -> some View {
        ZStack {
            if current {
                Circle().stroke(Theme.ok.opacity(0.35), lineWidth: 1).frame(width: 15, height: 15)
                Circle().fill(Theme.ok).frame(width: 7, height: 7)
            } else {
                Circle().fill(expanded ? Theme.cream : Theme.bg).frame(width: 9, height: 9)
                Circle().strokeBorder(.white.opacity(expanded ? 0.9 : 0.3), lineWidth: 1.5).frame(width: 9, height: 9)
            }
        }
        .frame(width: 15, height: 15)
        .padding(.leading, Self.dotX - 7.5)
        .padding(.top, Self.dotY - 7.5)
    }
}

// MARK: - Nouveautés d'une mise à jour

/// La feuille des nouveautés : captures, l'app qui arrive, le saut de version, les notes en décalé.
struct ChangelogSheet: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    let entry: AppEntry
    @State private var shown = false

    var body: some View {
        let accent = Theme.accent(entry.accent)
        let release = hub.releases[entry.id]
        VStack(spacing: 0) {
            Carousel(urls: images(release), accent: accent, symbol: entry.symbol, corner: 0)
                .frame(height: 300)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.bg], startPoint: .top, endPoint: .bottom).frame(height: 80)
                        .allowsHitTesting(false)
                }

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    AppIcon(entry: entry, size: 68)
                        .scaleEffect(shown || reduce ? 1 : 0.82)
                        .blur(radius: shown || reduce ? 0 : 8)
                        .opacity(shown ? 1 : 0)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(entry.name) \(release?.version ?? "")")
                            .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                            .foregroundStyle(Theme.cream)
                        jump(release)
                    }
                    .opacity(shown ? 1 : 0)
                    .offset(x: shown || reduce ? 0 : -10)
                    Spacer()
                }

                ScrollView {
                    FicheNotes(text: release?.notes ?? "", startDelay: 0.3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                }
                .frame(maxHeight: 220)
                .scrollIndicators(.automatic)

                HStack(spacing: 12) {
                    Button("Plus tard") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.surfaceHi, in: Capsule())
                        .keyboardShortcut(.cancelAction)
                    if let page = release?.page {
                        Link(destination: page) {
                            Label("Sur GitHub", systemImage: "arrow.up.right").font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    ActionButton(entry: entry, large: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .frame(width: 660)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.8).delay(0.12)) { shown = true }
        }
        .onDisappear {
            // ouverte pour une capture (OSAHUB_CHANGELOG) : cette version n'est pas marquée vue
            if ProcessInfo.processInfo.environment["OSAHUB_CHANGELOG"] == nil { hub.changelogClosed(entry) }
        }
    }

    /// « 1.2 → 1.3 · 4 nouveautés · publiée le … »
    @ViewBuilder private func jump(_ r: Release?) -> some View {
        let count = Notes.blocks(r?.notes ?? "").filter { if case .bullet = $0 { return true }; return false }.count
        let date = r?.date.map { "publiée le \($0.formatted(date: .abbreviated, time: .omitted))" }
        HStack(spacing: 8) {
            if let i = hub.installed[entry.id], let r, i.version != r.version {
                FicheVersionChip(version: i.version)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.faint)
                FicheVersionChip(version: r.version, strong: true)
            }
            Text([count > 1 ? "\(count) nouveautés" : nil, date].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12.5)).foregroundStyle(Theme.faint)
        }
    }

    private func images(_ r: Release?) -> [URL] {
        let own = r?.images ?? []
        return own.isEmpty ? entry.screenshots : own
    }
}

// MARK: - Pied de page

struct Footer: View {
    @EnvironmentObject private var hub: Hub

    var body: some View {
        HStack(spacing: 16) {
            HubLogo(size: 13)
            Text("v\(Hub.version)").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Theme.faint)
            if let r = hub.selfRelease {
                Button {
                    hub.updateSelf()
                } label: {
                    switch hub.selfJob {
                    case .downloading(let p)?: Text("Téléchargement \(Int(p * 100)) %")
                    case .failed(let m)?: Text("Échec : \(m)").lineLimit(1)
                    default: Label("OsaHUB \(r.version) : mettre à jour", systemImage: "arrow.down.circle.fill")
                    }
                }
                .buttonStyle(PillStyle())
            }
            Spacer()
            Toggle("Ouvrir à la connexion", isOn: Binding(get: { hub.launchAtLogin }, set: { hub.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.faint)
        }
        .padding(.top, 8)
    }
}

// MARK: - Barre des menus

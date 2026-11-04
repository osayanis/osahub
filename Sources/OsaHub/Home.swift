import SwiftUI
import AppKit

struct RootView: View {
    @MainActor static var hiddenOnce = false
    @EnvironmentObject private var hub: Hub
    @Environment(\.openWindow) private var openWindow
    @State private var selected: AppEntry?
    /// Les nouveautés attendent la fin de l'ouverture (et l'arrivée des cartes) pour s'afficher.
    @State private var sheetsAllowed = false
    /// L'accueil a défilé : la barre du haut prend un fond flou et un trait.
    @State private var scrolled = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if !hub.onboarded {
                // Premier lancement : l'accueil (merci, la suite Osa, entrer) ; ensuite seulement
                // le logo vivant s'envole vers la barre, comme à chaque ouverture.
                OnboardingView { hub.finishOnboarding() }
                    .transition(.opacity)
                    .zIndex(5)
            } else {
                main
            }
        }
        .animation(.easeInOut(duration: 0.6), value: hub.onboarded)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: hub.palette)
        .preferredColorScheme(.dark)
        .modifier(RootSheets(sheetsAllowed: $sheetsAllowed))
        .onAppear(perform: appeared)
    }

    @ViewBuilder private var main: some View {
        ZStack {
            if hub.splashDone {
                Backdrop().transition(.opacity)
                Group {
                    if let s = selected {
                        DetailView(entry: s) { go(nil) }
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                    } else {
                        HomeView(scrolled: $scrolled) { go($0) }
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .transition(.opacity)
                // sur l'accueil, la barre suit le défilement ; sur une fiche, le dégradé habituel
                TopBar(scrolled: selected == nil ? scrolled : nil).transition(.opacity)
            }
            LivingLogo(docked: hub.splashDone, finish: {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.86)) { hub.splashDone = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    sheetsAllowed = ProcessInfo.processInfo.environment["OSAHUB_NO_SHEETS"] == nil
                }
            }, tap: { go(nil) })
            if hub.palette {
                CommandPalette { go($0) }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
    }

    private func appeared() {
        // OSAHUB_NO_SHEETS=1 : captures sans la feuille des nouveautés (et sans la marquer vue)
        if ProcessInfo.processInfo.environment["OSAHUB_NO_SHEETS"] != nil { sheetsAllowed = false; return }
        if hub.splashDone { sheetsAllowed = true }
        // Pour les captures : OSAHUB_OPEN=<id> ouvre directement la fiche d'une app.
        if ProcessInfo.processInfo.environment["OSAHUB_PALETTE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { hub.palette = true }
        }
        if let id = ProcessInfo.processInfo.environment["OSAHUB_OPEN"] {
            selected = hub.entries.first { $0.id == id }
        }
        hub.openMain = { [openWindow] in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        // Relancé par une mise à jour automatique : la fenêtre se referme aussitôt.
        if Hub.autoUpdated && !RootView.hiddenOnce {
            RootView.hiddenOnce = true
            DispatchQueue.main.async {
                for w in NSApp.windows where w.isVisible && w.styleMask.contains(.titled) && !(w is NSPanel) { w.close() }
            }
        }
    }

    private func go(_ e: AppEntry?) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { selected = e }
    }
}

/// Les feuilles et confirmations de la fenêtre principale.
private struct RootSheets: ViewModifier {
    @EnvironmentObject private var hub: Hub
    @Binding var sheetsAllowed: Bool

    func body(content: Content) -> some View {
        content
        .sheet(item: Binding(get: { sheetsAllowed ? hub.changelog : nil }, set: { hub.changelog = $0 })) { e in
            ChangelogSheet(entry: e).environmentObject(hub)
        }
        .confirmationDialog(hub.uninstallAsk.map { "Mettre \($0.name) à la Corbeille ?" } ?? "",
                            isPresented: Binding(get: { hub.uninstallAsk != nil }, set: { if !$0 { hub.uninstallAsk = nil } }),
                            presenting: hub.uninstallAsk) { e in
            Button("Mettre à la Corbeille", role: .destructive) { hub.uninstall(e) }
            Button("Annuler", role: .cancel) {}
        } message: { e in
            Text("\(e.name) sera quitté s'il est ouvert. Tu pourras le récupérer dans la Corbeille ou le réinstaller depuis OsaHUB.")
        }
    }
}

// MARK: - Barre du haut

/// Fixe au-dessus du contenu : le logo vivant s'y range à gauche (LivingLogo), la recherche et la
/// vérification à droite. Le contenu glisse dessous en s'estompant.
struct TopBar: View {
    @EnvironmentObject private var hub: Hub
    /// nil : fiche d'une app (dégradé fixe). Sinon : rien en haut de l'accueil, puis un fond
    /// flou et un trait dès que le contenu passe dessous.
    var scrolled: Bool?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Spacer()
                SearchPill()
                RefreshButton()
            }
            .padding(.horizontal, 36)
            .frame(height: 64)
            .padding(.top, LivingLogo.dockedY - 32)
            .background(alignment: .top) {
                if let scrolled {
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(.ultraThinMaterial)
                        Theme.bg.opacity(0.72)
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                    .opacity(scrolled ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: scrolled)
                    .allowsHitTesting(false)
                } else {
                    LinearGradient(stops: [.init(color: Theme.bg, location: 0), .init(color: Theme.bg, location: 0.55), .init(color: Theme.bg.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .allowsHitTesting(false)
                }
            }
            Spacer()
        }
        .ignoresSafeArea()
    }
}

struct SearchPill: View {
    @EnvironmentObject private var hub: Hub
    @State private var hover = false

    var body: some View {
        Button { hub.palette = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                Text("Rechercher").font(.system(size: 12.5, weight: .medium))
                Text("⌘K").font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .foregroundStyle(.white.opacity(hover ? 0.85 : 0.55))
            .padding(.leading, 12).padding(.trailing, 6).frame(height: 32)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(hover ? 0.16 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct RefreshButton: View {
    @EnvironmentObject private var hub: Hub
    @State private var turns = 0.0

    var body: some View {
        HStack(spacing: 10) {
            if let d = hub.lastCheck {
                Text(hub.checking ? "Recherche…" : "Vérifié \(d.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .contentTransition(.opacity)
            }
            Button {
                Task { await hub.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(turns))
                    .frame(width: 32, height: 32)
                    .background(Theme.surfaceHi, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.cream)
            .disabled(hub.checking)
            .help("Rechercher des mises à jour (⌘R)")
        }
        .onChange(of: hub.checking) { _, on in
            if on { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turns += 360 } }
            else { withAnimation(.spring) { turns = (turns / 360).rounded(.up) * 360 } }
        }
    }
}

// MARK: - Accueil

struct HomeView: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var scrolled: Bool
    let select: (AppEntry) -> Void

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                StatusHero()
                    .appear(0)
                MaisonLauncher()
                    .appear(1)
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(title: "Les apps", detail: "clic droit pour les actions")
                        .appear(2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 20)], spacing: 20) {
                        ForEach(Array(hub.entries.enumerated()), id: \.element.id) { i, e in
                            AppCard(entry: e, index: i) { select(e) }
                        }
                    }
                }
                // le journal et les astuces côte à côte, à la même hauteur
                HStack(alignment: .top, spacing: 20) {
                    MaisonJournal()
                    MaisonTips()
                        .frame(width: 360)
                }
                .fixedSize(horizontal: false, vertical: true)
                .appear(4 + hub.entries.count)
                ServicesStrip()
                    .appear(5 + hub.entries.count)
                Footer()
            }
            .padding(.horizontal, 36)
            .padding(.top, 92)
            .padding(.bottom, 28)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
            .id("bas")
            .background {
                GeometryReader { g in
                    Color.clear.preference(key: MaisonScrollKey.self, value: g.frame(in: .named("accueil")).minY)
                }
            }
        }
        .coordinateSpace(.named("accueil"))
        .modifier(MaisonScrollWatch(scrolled: $scrolled))
        .onDisappear { scrolled = false }
        .scrollIndicators(.never)
        .background(DustField(reduceMotion: reduceMotion, intensity: 0.45))
        .onAppear {
            // captures : OSAHUB_SCROLL=bas descend en bas de l'accueil
            if ProcessInfo.processInfo.environment["OSAHUB_SCROLL"] == "bas" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { proxy.scrollTo("bas", anchor: .bottom) }
            }
        }
        }
    }
}

struct SectionTitle: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cream)
            if let detail { Text(detail).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Theme.faint) }
            Spacer()
        }
    }
}

/// Arrivée en douceur, décalée selon la position (l'accueil se construit sous les yeux).
/// Seulement à la première arrivée (MaisonIntro) : au retour d'une fiche ou en faisant défiler,
/// tout est déjà en place. Avec Reduce Motion, un simple fondu.
private struct Appear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = !MaisonIntro.playing
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .onAppear {
                MaisonIntro.mark()
                guard !shown else { return }
                let delay = 0.08 + Double(min(index, 8)) * 0.06
                withAnimation(reduceMotion ? .easeOut(duration: 0.3).delay(delay) : .spring(response: 0.55, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func appear(_ index: Int) -> some View { modifier(Appear(index: index)) }
}

// MARK: - L'état du moment, avec la mascotte

struct StatusHero: View {
    @EnvironmentObject private var hub: Hub
    @State private var hop = 0

    var body: some View {
        VStack(spacing: 0) {
            top
            // le trait se remplit pendant les téléchargements
            Rectangle().fill(Theme.line).frame(height: 1)
                .overlay(alignment: .leading) {
                    if let p = overall {
                        GeometryReader { g in
                            Rectangle().fill(.white.opacity(0.7))
                                .frame(width: max(8, g.size.width * p))
                                .animation(.easeOut(duration: 0.25), value: p)
                        }
                        .transition(.opacity)
                    }
                }
            MaisonVitals()
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: actionKey)
        .onChange(of: hub.jobs) { old, new in
            // une installation vient de finir : la mascotte saute
            if new.values.contains(.done) && !old.values.contains(.done) { hop += 1 }
        }
        .onChange(of: hub.updates.count) { _, n in if n > 0 { hop += 1 } }
    }

    private var top: some View {
        HStack(spacing: 18) {
            Mascot(mood: mood, arms: arms, size: 54, hop: hop)
                .frame(width: 86, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.interpolate)
                Text(subtitle)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
                    .contentTransition(.interpolate)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: title)
            Spacer(minLength: 12)
            actions
        }
        .padding(.vertical, 14).padding(.leading, 8).padding(.trailing, 18)
    }

    private var working: [AppEntry] {
        hub.entries.filter { e in
            switch hub.jobs[e.id] {
            case .downloading?, .installing?: return true
            default: return false
            }
        }
    }

    /// Avancement global des téléchargements en cours.
    private var overall: Double? {
        let list = working
        guard !list.isEmpty else { return nil }
        let sum = list.reduce(0.0) { acc, e in
            if case .downloading(let p)? = hub.jobs[e.id] { return acc + p * 0.9 }
            return acc + 0.95
        }
        return sum / Double(list.count)
    }

    private var mood: Mascot.Mood {
        if !working.isEmpty { return .busy }
        if hub.jobs.values.contains(.done) { return .happy }
        if hub.offline || (hub.limitedUntil != nil && hub.releases.isEmpty) { return .worried }
        if hub.checking && hub.lastCheck == nil { return .curious }
        if !hub.updates.isEmpty { return .excited }
        return .happy
    }

    private var arms: Mascot.Arms {
        if !working.isEmpty { return .work }
        if hub.jobs.values.contains(.done) { return .up }
        if hub.offline { return .rest }
        if !hub.updates.isEmpty { return .up }
        return .wave
    }

    private var title: String {
        let list = working
        if !list.isEmpty {
            return list.count == 1 ? "J'installe \(list[0].name)…" : "J'installe \(list.count) apps…"
        }
        if let done = hub.entries.first(where: { hub.jobs[$0.id] == .done }) { return "\(done.name) est à jour !" }
        if hub.offline { return "GitHub ne répond pas" }
        if hub.limitedUntil != nil && hub.releases.isEmpty { return "GitHub me demande de patienter" }
        if hub.checking && hub.lastCheck == nil { return "Je regarde s'il y a du nouveau…" }
        let n = hub.updates.count
        if n > 0 { return n == 1 ? "Une mise à jour t'attend" : "\(n) mises à jour t'attendent" }
        return "\(greeting), tout est à jour."
    }

    private var subtitle: String {
        if let p = overall { return "\(Int(p * 100)) % · je les quitte et les relance si elles étaient ouvertes" }
        if hub.offline { return "Vérifie ta connexion. Je réessaie toutes les 6 heures." }
        if let until = hub.limitedUntil, hub.releases.isEmpty {
            return "Sans compte, GitHub permet 60 vérifications par heure. Je pourrai regarder à \(until.formatted(date: .omitted, time: .shortened))."
        }
        let ups = hub.updates
        if !ups.isEmpty { return ups.map { "\($0.name) \(hub.releases[$0.id]?.version ?? "")" }.joined(separator: " · ") }
        if let done = justDone { return hub.running.contains(done.id) ? "Relancée dans sa nouvelle version." : "Elle t'attend dans Applications." }
        if let l = latest { return "Dernière sortie : \(l.entry.name) \(l.release.version), \(MaisonTime.ago(l.date))." }
        if hub.installed.isEmpty { return "Choisis une app plus bas : je l'installe et je la garde à jour." }
        return "Je vérifie les nouvelles versions toutes les 6 heures."
    }

    private var justDone: AppEntry? { hub.entries.first { hub.jobs[$0.id] == .done } }

    /// La dernière version sortie, toutes apps confondues.
    private var latest: (entry: AppEntry, release: Release, date: Date)? {
        hub.entries.compactMap { e in hub.releases[e.id].flatMap { r in r.date.map { (e, r, $0) } } }
            .max { $0.2 < $1.2 }
    }

    /// Apps publiées mais pas installées.
    private var installable: [AppEntry] {
        hub.entries.filter { hub.installed[$0.id] == nil && hub.releases[$0.id]?.zip != nil && hub.jobs[$0.id] == nil }
    }

    /// Ce qui décide des boutons affichés (pour animer le changement).
    private var actionKey: String {
        if !working.isEmpty { return "travail" }
        if !hub.updates.isEmpty { return "maj" }
        if justDone != nil { return "fini" }
        if hub.offline { return "horsligne" }
        if !installable.isEmpty { return "installer" }
        return latest == nil ? "rien" : "nouveautes"
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 5 || h >= 18 ? "Bonsoir" : "Bonjour"
    }

    /// Une action utile selon le moment : mettre à jour, ouvrir ce qui vient d'être installé,
    /// réessayer, installer ce qui manque, ou lire les nouveautés de la dernière sortie.
    @ViewBuilder private var actions: some View {
        let ups = hub.updates
        Group {
            switch actionKey {
            case "maj":
                HStack(spacing: 10) {
                    Button("Nouveautés") { hub.changelog = ups.first }
                        .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
                    Button { hub.updateAll() } label: {
                        Label(ups.count == 1 ? "Mettre à jour" : "Tout mettre à jour", systemImage: "arrow.down")
                    }
                    .buttonStyle(PillStyle())
                }
            case "fini":
                if let e = justDone, !hub.running.contains(e.id) {
                    Button("Ouvrir \(e.name)") { hub.open(e) }.buttonStyle(PillStyle())
                }
            case "horsligne":
                Button { Task { await hub.refresh() } } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
                    .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
                    .disabled(hub.checking)
            case "installer":
                let list = installable
                Button {
                    for e in list { hub.install(e) }
                } label: {
                    Label(list.count == 1 ? "Installer \(list[0].name)" : "Installer les \(list.count) apps", systemImage: "arrow.down")
                }
                .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
            case "nouveautes":
                if let l = latest {
                    Button("Nouveautés d’\(l.entry.name)") { hub.changelog = l.entry }
                        .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
                }
            default:
                EmptyView()
            }
        }
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .id(actionKey)
    }
}

// MARK: - Carte d'une app

struct AppCard: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: AppEntry
    var index = 0
    let open: () -> Void
    @State private var hover = false
    @State private var pointer: CGPoint?
    @State private var size: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                Color.clear
                    .overlay {
                        RemoteImage(url: entry.screenshots.first, mode: .fill) {
                            ZStack {
                                LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.26), Color(red: 0.1, green: 0.1, blue: 0.14)], startPoint: .top, endPoint: .bottom)
                                Image(systemName: entry.symbol).font(.system(size: 50, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .scaleEffect(hover && !reduceMotion ? 1.04 : 1)
                        // l'image glisse un peu à l'opposé du pointeur : effet de profondeur
                        .offset(x: -tilt.y * 1.6, y: tilt.x * 1.2)
                    }
                    .frame(height: 200)
                    .clipped()
                    .overlay(LinearGradient(colors: [.clear, .clear, Theme.bg.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                HStack {
                    if hub.running.contains(entry.id) { RunningBadge() }
                    Spacer()
                    if hub.hasUpdate(entry) {
                        Badge(text: "Nouvelle version", strong: true)
                    } else if hub.isComingSoon(entry) {
                        Badge(text: "Bientôt")
                    } else if fresh {
                        // version sortie il y a moins de 3 jours, déjà installée : ses nouveautés en un clic
                        Button { hub.changelog = entry } label: {
                            Label("Nouveautés", systemImage: "sparkles").labelStyle(BadgeLabel())
                        }
                        .buttonStyle(MaisonPress())
                        .help("Ce qui change dans la \(hub.releases[entry.id]?.version ?? "")")
                    } else if hub.autoUpdate.contains(entry.id) {
                        Badge(text: "Auto")
                    }
                }
                .padding(12)
            }
            .frame(height: 200)
            .clipped()

            HStack(alignment: .center, spacing: 14) {
                AppIcon(entry: entry, size: 56)
                    .offset(y: -18)
                    .padding(.bottom, -18)
                    .scaleEffect(hover && !reduceMotion ? 1.05 : 1, anchor: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.cream)
                    // deux lignes réservées : les cartes d'une même rangée gardent la même hauteur
                    Text(entry.tagline).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2, reservesSpace: true)
                }
                Spacer(minLength: 8)
                ActionButton(entry: entry)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)

            StatusLine(entry: entry)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
        .background(Theme.surface)
        // un reflet suit le pointeur
        .overlay {
            if let p = pointer {
                RadialGradient(colors: [.white.opacity(0.09), .clear], center: UnitPoint(x: p.x / max(1, size.width), y: p.y / max(1, size.height)),
                               startRadius: 0, endRadius: 260)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(hover ? 0.2 : 0.08), lineWidth: 1))
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
        .rotation3DEffect(.degrees(tilt.x), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(tilt.y), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(hover ? 0.5 : 0.3), radius: hover ? 24 : 14, y: hover ? 14 : 8)
        .offset(y: hover && !reduceMotion ? -3 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: open)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) { pointer = p; hover = true }
            case .ended:
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { pointer = nil; hover = false }
            }
        }
        .contextMenu { AppMenu(entry: entry, open: open) }
        .appear(index + 3)
    }

    /// Version installée sortie il y a moins de 3 jours.
    private var fresh: Bool {
        guard let i = hub.installed[entry.id], let r = hub.releases[entry.id], let d = r.date,
              !Version.isNewer(r.version, than: i.version) else { return false }
        return Date().timeIntervalSince(d) < 3 * 86400
    }

    /// Inclinaison (degrés) selon la position du pointeur : 3° au bord (rien avec Reduce Motion).
    private var tilt: (x: Double, y: Double) {
        guard !reduceMotion, let p = pointer, size.width > 0 else { return (0, 0) }
        let nx = (p.x / size.width) * 2 - 1, ny = (p.y / size.height) * 2 - 1
        return (-ny * 2.5, nx * 3)
    }
}

/// Les actions d'une app (clic droit sur sa carte, menu « … » de sa fiche).
struct AppMenu: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    var open: (() -> Void)?

    var body: some View {
        let installed = hub.installed[entry.id] != nil
        if installed {
            Button("Ouvrir \(entry.name)") { hub.open(entry) }
        }
        if hub.running.contains(entry.id) {
            Button("Quitter") { hub.quitApp(entry) }
            Button("Relancer") { hub.relaunchApp(entry) }
        }
        if hub.hasUpdate(entry) {
            Button("Mettre à jour en \(hub.releases[entry.id]?.version ?? "")") { hub.install(entry) }
        } else if !installed, hub.releases[entry.id]?.zip != nil {
            Button("Installer") { hub.install(entry) }
        }
        Divider()
        if let open { Button("Voir la fiche") { open() } }
        if installed {
            Toggle("Mettre à jour automatiquement", isOn: Binding(get: { hub.autoUpdate.contains(entry.id) }, set: { hub.setAutoUpdate(entry, $0) }))
            Button("Afficher dans le Finder") { hub.revealInFinder(entry) }
        }
        Button("Voir sur GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/\(entry.repo)")!) }
        if hub.canUninstall(entry) {
            Divider()
            Button("Mettre à la Corbeille…", role: .destructive) { hub.uninstallAsk = entry }
        }
    }
}

struct Badge: View {
    let text: String
    var strong = false
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(strong ? .black : .white.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(strong ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.black.opacity(0.45)), in: Capsule())
    }
}

/// Le style des badges de carte, pour un Label (icône + texte).
struct BadgeLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 9, weight: .bold))
            configuration.title
        }
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
        .contentShape(Capsule())
    }
}

/// « Ouverte », avec un point vert qui respire.
struct RunningBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill").font(.system(size: 6))
                .foregroundStyle(Theme.ok)
                .symbolEffect(.pulse, options: .repeating)
            Text("Ouverte")
        }
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.5), in: Capsule())
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

// MARK: - Les sites OsaLabs

struct ServicesStrip: View {
    @EnvironmentObject private var hub: Hub

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "En ligne", detail: "les sites OsaLabs, vérifiés toutes les 5 minutes")
            HStack(spacing: 12) {
                ForEach(Hub.serviceList) { s in ServiceTile(service: s, state: hub.services[s.id] ?? .unknown) }
            }
        }
    }
}

struct ServiceTile: View {
    let service: Hub.Service
    let state: Hub.ServiceState
    @State private var hover = false

    var body: some View {
        Button { NSWorkspace.shared.open(service.url) } label: {
            HStack(spacing: 10) {
                Image(systemName: service.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.cream)
                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 6, height: 6)
                            .shadow(color: color.opacity(0.8), radius: up ? 3 : 0)
                        Text(label).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Theme.faint)
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(hover ? 0.6 : 0))
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(hover ? 0.16 : 0.07)))
            .offset(y: hover ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { hover = h } }
        .animation(.easeOut(duration: 0.3), value: state)
        .help(service.url.absoluteString)
    }

    private var up: Bool { if case .up = state { return true }; return false }
    private var color: Color {
        switch state {
        case .up: return Theme.ok
        case .down: return Theme.red
        case .unknown: return .white.opacity(0.25)
        }
    }
    private var label: String {
        switch state {
        case .up(let ms): return "en ligne · \(ms) ms"
        case .down: return "ne répond pas"
        case .unknown: return "vérification…"
        }
    }
}

// MARK: - ⌘K

/// Recherche rapide : une app, une action, au clavier.
struct CommandPalette: View {
    @EnvironmentObject private var hub: Hub
    let show: (AppEntry) -> Void
    @State private var query = ""
    @State private var index = 0
    @State private var shown = false
    @FocusState private var focused: Bool
    @Namespace private var ns

    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        var entry: AppEntry?
        let run: () -> Void
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(shown ? 0.5 : 0).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.faint)
                    TextField("Une app, une action…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .medium))
                        .focused($focused)
                        .onSubmit { run() }
                    Text("esc").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.faint)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .padding(.horizontal, 18).frame(height: 54)
                Rectangle().fill(Theme.line).frame(height: 1)
                let list = items
                if list.isEmpty {
                    Text("Rien ne correspond à « \(query) ».")
                        .font(.system(size: 13)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity).padding(.vertical, 26)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(list.prefix(8).enumerated()), id: \.element.id) { i, item in
                            row(item, selected: i == min(index, list.count - 1))
                                .onTapGesture { index = i; run() }
                                .onHover { if $0 { index = i } }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 580)
            .background(Color(red: 0.075, green: 0.075, blue: 0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
            .scaleEffect(shown ? 1 : 0.96)
            .offset(y: shown ? 0 : -12)
            .opacity(shown ? 1 : 0)
            .padding(.top, 110)
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { shown = true }
            focused = true
        }
        .onChange(of: query) { _, _ in index = 0 }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let e = item.entry { AppIcon(entry: e, size: 30) }
                else {
                    Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 30, height: 30).background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.cream)
                Text(item.subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "return").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.faint) }
        }
        .padding(.horizontal, 10).frame(height: 46)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08))
                    .matchedGeometryEffect(id: "sel", in: ns)
            }
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: selected)
    }

    private var items: [Item] {
        var all: [Item] = []
        let ups = hub.updates
        if !ups.isEmpty {
            all.append(Item(id: "tout", title: ups.count == 1 ? "Mettre à jour \(ups[0].name)" : "Tout mettre à jour",
                            subtitle: ups.map(\.name).joined(separator: ", "), symbol: "arrow.down.circle") { hub.updateAll() })
        }
        for e in hub.entries {
            let installed = hub.installed[e.id] != nil
            if hub.hasUpdate(e) {
                all.append(Item(id: "maj.\(e.id)", title: "Mettre à jour \(e.name)", subtitle: "v\(hub.installed[e.id]?.version ?? "") → v\(hub.releases[e.id]?.version ?? "")",
                                symbol: "arrow.down", entry: e) { hub.install(e) })
            }
            if installed {
                all.append(Item(id: "ouvrir.\(e.id)", title: "Ouvrir \(e.name)", subtitle: hub.running.contains(e.id) ? "déjà ouverte" : e.tagline,
                                symbol: "arrow.up.forward.app", entry: e) { hub.open(e) })
            } else if hub.releases[e.id]?.zip != nil {
                all.append(Item(id: "installer.\(e.id)", title: "Installer \(e.name)", subtitle: e.tagline, symbol: "arrow.down.circle", entry: e) { hub.install(e) })
            }
            all.append(Item(id: "fiche.\(e.id)", title: "\(e.name) : la fiche", subtitle: "captures, nouveautés, versions", symbol: "doc.text", entry: e) { show(e) })
            if hub.running.contains(e.id) {
                all.append(Item(id: "quitter.\(e.id)", title: "Quitter \(e.name)", subtitle: "la fermer proprement", symbol: "xmark.circle", entry: e) { hub.quitApp(e) })
            }
        }
        all.append(Item(id: "verif", title: "Rechercher des mises à jour", subtitle: "toutes les apps", symbol: "arrow.clockwise") { Task { await hub.refresh() } })
        for s in Hub.serviceList {
            all.append(Item(id: "site.\(s.id)", title: "Ouvrir \(s.name)", subtitle: s.url.host() ?? "", symbol: s.symbol) { NSWorkspace.shared.open(s.url) })
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all.filter { !$0.id.hasPrefix("fiche.") && !$0.id.hasPrefix("site.") } }
        return all.filter { matches(q, $0.title + " " + $0.subtitle) }
    }

    /// Chaque mot tapé doit se trouver quelque part (sans tenir compte des accents ni des majuscules).
    private func matches(_ q: String, _ text: String) -> Bool {
        let t = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return q.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(separator: " ").allSatisfy { t.contains($0) }
    }

    private func move(_ d: Int) {
        let n = min(8, items.count)
        guard n > 0 else { return }
        index = (index + d + n) % n
    }

    private func run() {
        let list = items
        guard !list.isEmpty else { return }
        let item = list[min(index, list.count - 1)]
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { item.run() }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { hub.palette = false }
    }
}

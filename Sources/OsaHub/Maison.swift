import SwiftUI

// L'écran principal, en plus du bandeau et des cartes : les chiffres de la suite, le lancement
// rapide (⌘1…⌘9), le journal des dernières versions et les astuces. Sobre comme OsaWallpaper :
// blanc à différentes opacités, la couleur seulement pour un état.

// MARK: - Chiffres (sous le bandeau, dans la même carte)

/// Quatre chiffres en ligne, sous le bandeau : le bandeau dit l'état du moment, eux disent la
/// suite en un coup d'œil. Ils montent depuis zéro à la première arrivée, puis suivent sans bruit.
struct MaisonVitals: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var counted = !MaisonIntro.playing

    var body: some View {
        let installed = hub.installed.count
        let upToDate = hub.entries.filter { hub.installed[$0.id] != nil && !hub.hasUpdate($0) }.count
        let auto = hub.autoUpdate.filter { hub.installed[$0] != nil }.count
        HStack(spacing: 0) {
            cell(installed, of: hub.entries.count, label: installed > 1 ? "installées" : "installée")
            divider
            cell(hub.running.count, label: hub.running.count > 1 ? "ouvertes" : "ouverte", live: !hub.running.isEmpty)
            divider
            cell(upToDate, of: installed, label: "à jour", dim: installed == 0)
            divider
            cell(auto, of: installed, label: "en mise à jour auto", dim: installed == 0)
        }
        .frame(height: 46)
        .onAppear {
            guard !counted else { return }
            if reduceMotion { counted = true; return }
            // les chiffres montent depuis zéro, une fois par lancement
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.92)) { counted = true }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 18)
    }

    private func cell(_ n: Int, of total: Int? = nil, label: String, live: Bool = false, dim: Bool = false) -> some View {
        let v = counted ? n : 0
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(v)")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(dim ? Theme.faint : Theme.cream)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(v)))
                    .animation(.snappy(duration: 0.3), value: v)
                if let total {
                    Text("/\(total)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.faint)
                }
            }
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(1)
            if live {
                Circle().fill(Theme.ok).frame(width: 6, height: 6)
                    .modifier(MaisonPulse())
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 1 }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Lancement rapide

struct MaisonLauncher: View {
    @EnvironmentObject private var hub: Hub

    var body: some View {
        let apps = hub.entries.filter { hub.installed[$0.id] != nil }
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Lancement rapide", detail: "⌘1 à ⌘\(min(apps.count, 9)) depuis cette fenêtre")
                // jusqu'à 4 par rangée, toutes de la même largeur
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(apps.count, 4)), spacing: 12) {
                    ForEach(Array(apps.prefix(9).enumerated()), id: \.element.id) { i, e in
                        MaisonLaunchTile(entry: e, shortcut: i + 1, running: hub.running.contains(e.id)) { hub.open(e) }
                    }
                }
            }
        }
    }
}

private struct MaisonLaunchTile: View {
    let entry: AppEntry
    let shortcut: Int
    let running: Bool
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var bounce = 0

    var body: some View {
        Button {
            if !reduceMotion { bounce += 1 }
            open()
        } label: {
            HStack(spacing: 10) {
                AppIcon(entry: entry, size: 34)
                    .keyframeAnimator(initialValue: 0.0, trigger: bounce) { v, y in v.offset(y: y) } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(-7, duration: 0.16, spring: .snappy)
                            SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.cream).lineLimit(1)
                    HStack(spacing: 5) {
                        if running {
                            // statique : le bandeau a déjà son point qui respire
                            Circle().fill(Theme.ok).frame(width: 5, height: 5)
                            Text("ouverte")
                        } else {
                            Text("ouvrir")
                        }
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                }
                Spacer(minLength: 6)
                Text("⌘\(shortcut)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .opacity(hover ? 1 : 0.8)
            }
            .padding(.leading, 8).padding(.trailing, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Theme.surfaceHi : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(hover ? 0.16 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MaisonPress())
        .keyboardShortcut(KeyEquivalent(Character("\(shortcut)")), modifiers: .command)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .help("Ouvrir \(entry.name)")
    }
}

// MARK: - Journal de la suite

struct MaisonJournal: View {
    @EnvironmentObject private var hub: Hub

    var body: some View {
        let items = hub.entries.compactMap { e -> (AppEntry, Release)? in
            guard let r = hub.releases[e.id], r.zip != nil else { return nil }
            return (e, r)
        }
        .sorted { ($0.1.date ?? .distantPast) > ($1.1.date ?? .distantPast) }

        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Journal de la suite", detail: "les dernières versions")
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(hub.checking ? "Je récupère les dernières versions…" : "Rien pour l’instant.")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                ForEach(Array(items.enumerated()), id: \.element.0.id) { i, item in
                    MaisonJournalRow(entry: item.0, release: item.1, first: i == 0, last: i == items.count - 1,
                                     pending: hub.hasUpdate(item.0)) {
                        hub.changelog = item.0
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .maisonCard()
        }
    }
}

private struct MaisonJournalRow: View {
    let entry: AppEntry
    let release: Release
    let first: Bool
    let last: Bool
    /// Version pas encore installée sur ce Mac.
    let pending: Bool
    let open: () -> Void
    @State private var hover = false

    private var fresh: Bool { (release.date.map { Date().timeIntervalSince($0) < 3 * 86400 }) ?? false }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 14) {
                // la frise
                VStack(spacing: 0) {
                    Rectangle().fill(first ? .clear : Theme.line).frame(width: 1, height: 14)
                    ZStack {
                        // seule la toute dernière sortie respire ; les autres récentes restent pleines
                        if fresh && first { Circle().fill(.white).frame(width: 9, height: 9).modifier(MaisonPulse(scale: 2.4)) }
                        Circle().fill(fresh ? Theme.cream : .white.opacity(0.3)).frame(width: 9, height: 9)
                    }
                    Rectangle().fill(last ? .clear : Theme.line).frame(width: 1).frame(maxHeight: .infinity)
                }
                .frame(width: 12)
                AppIcon(entry: entry, size: 30).padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.cream)
                        Text(release.version).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.dim)
                        if pending {
                            Text("pas encore installée").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.cream)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Theme.surfaceHi, in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                        }
                    }
                    Text(Notes.summary(release.notes) ?? release.title)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                .padding(.top, 8)
                Spacer(minLength: 8)
                Text(release.date.map(MaisonTime.ago) ?? "")
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Theme.faint)
                    .padding(.top, 10)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(hover ? 0.5 : 0)).padding(.top, 11)
                    .offset(x: hover ? 0 : -4)
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hover ? 0.04 : 0)).padding(.horizontal, 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .help("Voir les nouveautés de \(entry.name)")
    }
}

// MARK: - Astuces

struct MaisonTips: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var hover = false
    @State private var forward = true

    private struct Tip {
        let symbol: String
        let title: String
        let text: String
        var action: String?
    }

    private let tips: [Tip] = [
        Tip(symbol: "command", title: "Tout trouver avec ⌘K",
            text: "Une app, une mise à jour, une action : tape quelques lettres, sans lâcher le clavier.", action: "Essayer"),
        Tip(symbol: "menubar.rectangle", title: "Une seule mascotte",
            text: "Quand OsaHUB tourne, OsaWallpaper range son icône dans le menu d’OsaHUB : aperçu de l’écran verrouillé, réglages, tout y est."),
        Tip(symbol: "person.2.fill", title: "Ton code ami OsaNotch",
            text: "Partage ton code à 6 chiffres : vous pourrez vous montrer votre écran avec OsaCast ou écouter la même musique avec OsaParty."),
        Tip(symbol: "arrow.triangle.2.circlepath", title: "Des mises à jour sans y penser",
            text: "Active la mise à jour auto dans la fiche d’une app : OsaHUB s’en occupe dès qu’elle est fermée."),
        Tip(symbol: "keyboard", title: "⌘1 à ⌘9",
            text: "Depuis cette fenêtre, ouvre tes apps installées d’un raccourci, dans l’ordre du lancement rapide."),
        Tip(symbol: "hand.wave.fill", title: "Revoir l’accueil",
            text: "Envie de revoir la présentation de la suite Osa ? Elle est toujours là.", action: "Revoir"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Astuces", detail: "\(index + 1) sur \(tips.count)")
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    card(tips[index])
                        .id(index)
                        .transition(transition)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .clipped()
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    ForEach(0..<tips.count, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == index ? 0.85 : 0.2))
                            .frame(width: i == index ? 16 : 5, height: 5)
                            .contentShape(Rectangle().inset(by: -5))
                            .onTapGesture { go(i) }
                    }
                    Spacer()
                    arrow("chevron.left") { go(index - 1) }
                    arrow("chevron.right") { go(index + 1) }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
            }
            .padding(18)
            .frame(maxHeight: .infinity, alignment: .top)
            .maisonCard()
            .onHover { hover = $0 }
        }
        .task {
            // avance seule toutes les 7 s, sauf quand le pointeur est dessus
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                if !hover { go(index + 1) }
            }
        }
    }

    private func card(_ t: Tip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: t.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.surfaceHi))
            Text(t.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cream)
            Text(t.text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.dim).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let a = t.action {
                Button(a) { act(t) }.buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
                    .padding(.top, 2)
            }
        }
    }

    private func arrow(_ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
                .frame(width: 24, height: 24).background(Circle().fill(Theme.surfaceHi))
        }
        .buttonStyle(MaisonPress())
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let dx: CGFloat = forward ? 40 : -40
        return .asymmetric(insertion: .offset(x: dx).combined(with: .opacity),
                           removal: .offset(x: -dx).combined(with: .opacity))
    }

    private func go(_ i: Int) {
        forward = i > index || (index == tips.count - 1 && i == tips.count)
        let n = (i % tips.count + tips.count) % tips.count
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { index = n }
    }

    private func act(_ t: Tip) {
        if t.symbol == "command" { hub.palette = true }
        if t.symbol == "hand.wave.fill" { hub.replayOnboarding() }
    }
}

// MARK: - Outils

/// La première arrivée sur l'accueil (une fois par lancement) se construit sous les yeux ;
/// au retour d'une fiche, tout est déjà là : fréquent = rapide.
@MainActor enum MaisonIntro {
    private static var start: Date?
    /// Vrai pendant la première seconde et demie d'accueil.
    static var playing: Bool { start.map { Date().timeIntervalSince($0) < 1.5 } ?? true }
    static func mark() { if start == nil { start = Date() } }
}

/// L'accueil a-t-il défilé ? macOS 15+ : la géométrie du défilement ; macOS 14 : la position
/// du contenu remontée par MaisonScrollKey.
struct MaisonScrollWatch: ViewModifier {
    @Binding var scrolled: Bool
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { g in
                g.contentOffset.y + g.contentInsets.top > 4
            } action: { _, s in
                if s != scrolled { scrolled = s }
            }
        } else {
            content.onPreferenceChange(MaisonScrollKey.self) { y in
                let s = y < -4
                if s != scrolled { scrolled = s }
            }
        }
    }
}

/// Position du contenu de l'accueil (pour la barre du haut, macOS 14).
struct MaisonScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

enum MaisonTime {
    static func ago(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 3600 { return "il y a \(max(1, Int(s / 60))) min" }
        if s < 86400 { return "il y a \(Int(s / 3600)) h" }
        let days = Int(s / 86400)
        if days == 1 { return "hier" }
        if days < 30 { return "il y a \(days) jours" }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Un point qui respire : une onde s'en échappe régulièrement.
struct MaisonPulse: ViewModifier {
    var scale: CGFloat = 2.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .background {
                if !reduceMotion {
                    content.scaleEffect(on ? scale : 1).opacity(on ? 0 : 0.6)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: on)
                }
            }
            .onAppear { on = true }
    }
}

struct MaisonPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Carte de la suite : blanc 0,05, trait 0,08.
    func maisonCard(radius: CGFloat = 16) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line))
    }
}

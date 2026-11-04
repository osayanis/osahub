import SwiftUI
import AppKit

// Les sections de la fiche d'une app (DetailView, dans Views.swift).

struct FicheSectionTitle: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.cream)
            if let detail { Text(detail).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.faint) }
            Spacer(minLength: 0)
        }
    }
}

/// Une carte de la suite : white 0.05, trait 0.08.
private struct FicheCard: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line))
    }
}

extension View {
    func ficheCard(_ radius: CGFloat = 14) -> some View { modifier(FicheCard(radius: radius)) }
}

// MARK: - En-tête

struct FicheHero: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    let scroll: FicheScroll

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            FicheParallaxIcon(entry: entry, scroll: scroll)
            FicheScrollFade(scroll: scroll) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.name)
                        .font(.system(size: 34, weight: .bold)).kerning(-0.9)
                        .foregroundStyle(Theme.cream)
                    Text(entry.tagline)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    StatusLine(entry: entry).padding(.top, 5)
                }
            }
            .ficheReveal(1)
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 8) {
                    ActionButton(entry: entry, large: true)
                    Menu {
                        AppMenu(entry: entry)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(Theme.surfaceHi, in: Circle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .foregroundStyle(Theme.cream)
                    .fixedSize()
                    .help("Plus d'actions")
                }
                if hub.running.contains(entry.id) {
                    HStack(spacing: 14) {
                        RunningBadge()
                        Button("Quitter") { hub.quitApp(entry) }
                        Button("Relancer") { hub.relaunchApp(entry) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .ficheReveal(2)
            .animation(FicheMotion.state, value: hub.running.contains(entry.id))
        }
    }
}

/// La grande icône : arrive en sortant du flou, puis descend moins vite que la page (parallaxe)
/// en rapetissant quand on fait défiler.
struct FicheParallaxIcon: View {
    let entry: AppEntry
    let scroll: FicheScroll
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    var body: some View {
        // effacée avant de pouvoir toucher les captures (décalage plafonné à 30 points)
        let s = scroll.scrolled
        let p = min(1, s / 190)
        AppIcon(entry: entry, size: 116)
            .scaleEffect((shown || reduce ? 1 : 0.86) * (reduce ? 1 : 1 - 0.12 * p))
            .offset(y: reduce ? 0 : min(s, 150) * 0.2)
            .opacity((shown ? 1 : 0) * (1 - 0.9 * p))
            .blur(radius: shown || reduce ? 0 : 10)
            .onAppear {
                withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.78).delay(0.04)) { shown = true }
            }
    }
}

/// Le texte de l'en-tête s'efface doucement quand il part sous la barre du haut.
struct FicheScrollFade<Content: View>: View {
    let scroll: FicheScroll
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let p = min(1, scroll.scrolled / 220)
        content()
            .opacity(1 - 0.75 * p)
            .offset(y: reduce ? 0 : min(scroll.scrolled, 200) * 0.1)
    }
}

// MARK: - Ce qu'elle fait

struct FicheFeatures: View {
    let entry: AppEntry
    let soon: Bool

    var body: some View {
        let list = FicheContent.features(entry.id)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                FicheSectionTitle(title: soon ? "Ce qu'elle fera" : "Ce qu'elle fait",
                                  detail: soon ? "bientôt dans OsaHUB" : nil)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 28, alignment: .top), GridItem(.flexible(), spacing: 28, alignment: .top)],
                          alignment: .leading, spacing: 22) {
                    ForEach(list, id: \.self) { f in
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: f.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 34, height: 34)
                                .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.cream)
                                Text(f.text).font(.system(size: 12.5)).foregroundStyle(Theme.dim)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Fonctionne avec

struct FicheLinks: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    let openApp: (AppEntry) -> Void

    var body: some View {
        let links = FicheContent.links(entry.id)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                FicheSectionTitle(title: "Fonctionne avec", detail: "la suite Osa se parle")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(links, id: \.self) { link in
                        FicheLinkTile(link: link, openApp: openApp)
                    }
                }
            }
        }
    }
}

private struct FicheLinkTile: View {
    @EnvironmentObject private var hub: Hub
    let link: FicheContent.Link
    let openApp: (AppEntry) -> Void
    @State private var hover = false

    var body: some View {
        let action = self.action
        Button { action?() } label: {
            HStack(spacing: 13) {
                icon.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.cream)
                        status
                    }
                    Text(link.text).font(.system(size: 12)).foregroundStyle(Theme.dim)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if let trailing {
                    Image(systemName: trailing)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(hover ? 0.75 : 0.35))
                        .offset(x: hover ? 2 : 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(hover && action != nil ? Theme.surfaceHi : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(hover && action != nil ? 0.14 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(FichePress(scale: 0.98))
        .disabled(action == nil)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .help(help)
    }

    private var app: AppEntry? {
        if case .app(let id) = link.target { return hub.entries.first { $0.id == id } }
        return nil
    }

    private var service: Hub.Service? {
        if case .service(let id) = link.target { return Hub.serviceList.first { $0.id == id } }
        return nil
    }

    private var name: String {
        switch link.target {
        case .app(let id): return app?.name ?? id
        case .service: return service?.name ?? ""
        case .hub: return "OsaHUB"
        case .web(let name, _, _): return name
        }
    }

    private var action: (() -> Void)? {
        switch link.target {
        case .app: return app.map { a in { openApp(a) } }
        case .service: return service.map { s in { NSWorkspace.shared.open(s.url) } }
        case .web(_, let url, _): return { NSWorkspace.shared.open(url) }
        case .hub: return nil
        }
    }

    private var trailing: String? {
        switch link.target {
        case .app: return "chevron.right"
        case .service, .web: return "arrow.up.right"
        case .hub: return nil
        }
    }

    private var help: String {
        switch link.target {
        case .app: return "Voir la fiche de \(name)"
        case .service(_): return service.map { "Ouvrir \($0.url.host() ?? $0.name)" } ?? ""
        case .web(_, let url, _): return "Ouvrir \(url.host() ?? "")"
        case .hub: return ""
        }
    }

    @ViewBuilder private var icon: some View {
        switch link.target {
        case .app:
            if let app { AppIcon(entry: app, size: 40) }
        case .hub:
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        case .service:
            symbolTile(service?.symbol ?? "globe")
        case .web(_, _, let symbol):
            symbolTile(symbol)
        }
    }

    private func symbolTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Theme.surfaceHi)
            .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    /// État du site, vérifié par OsaHUB toutes les 5 minutes.
    @ViewBuilder private var status: some View {
        if case .service(let id) = link.target {
            switch hub.services[id] ?? .unknown {
            case .up:
                Circle().fill(Theme.ok).frame(width: 6, height: 6).help("En ligne")
            case .down:
                Text("hors ligne").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.red)
            case .unknown:
                EmptyView()
            }
        }
    }
}

// MARK: - Nouveautés de la dernière version

struct FicheReleaseCard: View {
    let release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Nouveautés").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.cream)
                FicheVersionChip(version: release.version)
                if let d = release.date {
                    Text(d.formatted(date: .long, time: .omitted)).font(.system(size: 12.5)).foregroundStyle(Theme.faint)
                }
                Spacer()
                Link(destination: release.page) {
                    Label("GitHub", systemImage: "arrow.up.right").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Theme.dim)
            }
            NotesView(text: release.notes, accent: Theme.cream)
        }
        .padding(20)
        .ficheCard()
    }
}

struct FicheVersionChip: View {
    let version: String
    var strong = false
    var body: some View {
        Text("v\(version)")
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(strong ? Theme.ink : .white.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(strong ? AnyShapeStyle(Theme.cream) : AnyShapeStyle(Theme.surfaceHi), in: Capsule())
    }
}

// MARK: - Infos

struct FicheInfos: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry

    var body: some View {
        let installed = hub.installed[entry.id]
        let release = hub.releases[entry.id]
        VStack(alignment: .leading, spacing: 16) {
            FicheSectionTitle(title: "Infos")
            VStack(spacing: 0) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        cell("Installée", installed.map { "v\($0.version)" } ?? "Pas installée",
                             tint: installed != nil ? (hub.hasUpdate(entry) ? nil : Theme.ok) : nil)
                        cell("Dernière version", release.map { "v\($0.version)" } ?? (hub.isComingSoon(entry) ? "Pas encore publiée" : "…"))
                        cell("Publiée", release?.date.map { $0.formatted(date: .long, time: .omitted) } ?? "…",
                             sub: release?.date.map { $0.formatted(.relative(presentation: .named)) })
                    }
                    divider
                    GridRow {
                        ForEach(FicheContent.requirements(entry.id).prefix(2), id: \.self) { r in cell(r.label, r.value) }
                        sourceCell
                    }
                    if FicheContent.requirements(entry.id).count > 2 {
                        divider
                        GridRow {
                            ForEach(FicheContent.requirements(entry.id).dropFirst(2), id: \.self) { r in cell(r.label, r.value) }
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
                if let installed {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    locationRow(installed.url)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    autoRow
                }
            }
            .ficheCard()
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).gridCellColumns(3)
    }

    private func cell(_ label: String, _ value: String, sub: String? = nil, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.faint)
            HStack(spacing: 6) {
                if let tint { Circle().fill(tint).frame(width: 6, height: 6) }
                Text(value).font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.cream)
                    .lineLimit(1)
            }
            if let sub { Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.faint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var sourceCell: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Code source").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.faint)
            Link(destination: URL(string: "https://github.com/\(entry.repo)")!) {
                HStack(spacing: 4) {
                    Text(entry.repo).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(Theme.cream)
            .help("Ouvrir le dépôt sur GitHub")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func locationRow(_ url: URL) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Emplacement").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.faint)
                Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.cream)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Afficher dans le Finder") { hub.revealInFinder(entry) }
                .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var autoRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mise à jour automatique").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.cream)
                Text("Quand une version sort, OsaHUB l'installe tout seul, si l'app est fermée.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Toggle("Mise à jour automatique", isOn: Binding(get: { hub.autoUpdate.contains(entry.id) }, set: { hub.setAutoUpdate(entry, $0) }))
                .labelsHidden()
                .toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}

// MARK: - Barre flottante

/// Quand l'en-tête est parti en haut : l'app et son action restent à portée, en bas de la fenêtre.
struct FicheDock: View {
    let entry: AppEntry
    let toTop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(entry: entry, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream)
                StatusLine(entry: entry).font(.system(size: 11))
            }
            Spacer(minLength: 16)
            ActionButton(entry: entry)
            Button(action: toTop) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.cream)
                    .frame(width: 31, height: 31)
                    .background(Theme.surfaceHi, in: Circle())
            }
            .buttonStyle(FichePress(scale: 0.92))
            .help("Revenir en haut")
        }
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 8)
        .frame(width: 480)
        .background(Capsule().fill(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.96)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}

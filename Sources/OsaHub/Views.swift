import SwiftUI
import AppKit

struct RootView: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.openWindow) private var openWindow
    @State private var selected: AppEntry?
    /// Les nouveautés attendent la fin de l'ouverture (et l'arrivée des cartes) pour s'afficher.
    @State private var sheetsAllowed = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if hub.splashDone {
                Backdrop().transition(.opacity)
                Group {
                    if let s = selected {
                        DetailView(entry: s) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { selected = nil }
                        }
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .trailing).combined(with: .opacity)))
                    } else {
                        HomeView { e in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { selected = e }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.03)))
            } else {
                Splash {
                    withAnimation(.easeOut(duration: 0.55)) { hub.splashDone = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { sheetsAllowed = true }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: Binding(get: { sheetsAllowed ? hub.changelog : nil }, set: { hub.changelog = $0 })) { e in
            ChangelogSheet(entry: e).environmentObject(hub)
        }
        .onAppear {
            if hub.splashDone { sheetsAllowed = true }
            // Pour les captures : OSAHUB_OPEN=<id> ouvre directement la fiche d'une app.
            if let id = ProcessInfo.processInfo.environment["OSAHUB_OPEN"] {
                selected = hub.entries.first { $0.id == id }
            }
            hub.openMain = { [openWindow] in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// MARK: - Accueil

struct HomeView: View {
    @EnvironmentObject private var hub: Hub
    let select: (AppEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !hub.updates.isEmpty { UpdatesBanner() }
                if hub.offline { OfflineBanner() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 20)], spacing: 20) {
                    ForEach(Array(hub.entries.enumerated()), id: \.element.id) { i, e in
                        AppCard(entry: e, index: i)
                            .onTapGesture { select(e) }
                    }
                }
                Footer()
            }
            .padding(.horizontal, 36)
            .padding(.top, 46)
            .padding(.bottom, 28)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HubLogo(size: 26)
                Text("Toutes les apps OsaLabs, au même endroit.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            RefreshButton()
        }
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
            .help("Rechercher des mises à jour")
        }
        .onChange(of: hub.checking) { _, on in
            if on { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turns += 360 } }
            else { withAnimation(.spring) { turns = (turns / 360).rounded(.up) * 360 } }
        }
    }
}

struct UpdatesBanner: View {
    @EnvironmentObject private var hub: Hub

    var body: some View {
        let list = hub.updates
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 34, height: 34).background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(list.count == 1 ? "Une mise à jour est disponible" : "\(list.count) mises à jour sont disponibles")
                    .font(.system(size: 14, weight: .semibold))
                Text(list.map { "\($0.name) \(hub.releases[$0.id]?.version ?? "")" }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Button("Voir les nouveautés") { hub.changelog = list.first }
                .buttonStyle(PillStyle())
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct OfflineBanner: View {
    var body: some View {
        Label("GitHub ne répond pas : les versions affichées peuvent être anciennes.", systemImage: "wifi.slash")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
    }
}

// MARK: - Carte d'une app

struct AppCard: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    var index = 0
    @State private var hover = false
    @State private var shown = false

    var body: some View {
        let accent = Theme.accent(entry.accent)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .overlay {
                        RemoteImage(url: entry.screenshots.first, mode: .fill) {
                            ZStack {
                                LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.26), Color(red: 0.1, green: 0.1, blue: 0.14)], startPoint: .top, endPoint: .bottom)
                                Image(systemName: entry.symbol).font(.system(size: 50, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .scaleEffect(hover ? 1.05 : 1)
                    }
                    .frame(height: 200)
                    .clipped()
                .overlay(LinearGradient(colors: [.clear, .clear, Theme.bg.opacity(0.9)], startPoint: .top, endPoint: .bottom))

                if hub.hasUpdate(entry) {
                    Text("Nouvelle version")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.9), in: Capsule())
                        .padding(12)
                } else if hub.isComingSoon(entry) {
                    Text("Bientôt")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                }
            }
            .frame(height: 200)
            .clipped()

            HStack(alignment: .center, spacing: 14) {
                AppIcon(entry: entry, size: 56)
                    .offset(y: -18)
                    .padding(.bottom, -18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.cream)
                    Text(entry.tagline).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(hover ? 0.22 : 0.08), lineWidth: 1))
        .shadow(color: .black.opacity(hover ? 0.5 : 0.3), radius: hover ? 24 : 14, y: hover ? 14 : 8)
        .offset(y: hover ? -4 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hover = $0 }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: hover)
        // arrivée des cartes l'une après l'autre
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 26)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.08 + Double(index) * 0.07)) { shown = true }
        }
    }
}

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
        return "Recherche de la dernière version…"
    }
}

/// Installer / Mettre à jour / Ouvrir, avec l'avancement.
struct ActionButton: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    var large = false

    var body: some View {
        let accent = Theme.accent(entry.accent)
        Group {
            switch hub.jobs[entry.id] {
            case .downloading(let p)?:
                ProgressPill(progress: p, label: "\(Int(p * 100)) %", accent: accent, large: large)
            case .installing?:
                ProgressPill(progress: nil, label: "Installation…", accent: accent, large: large)
            case .done?:
                Label("Installée", systemImage: "checkmark")
                    .font(.system(size: large ? 14 : 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ok)
                    .padding(.horizontal, large ? 22 : 14).padding(.vertical, large ? 10 : 7)
                    .background(Theme.surfaceHi, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
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
                } else {
                    ProgressView().controlSize(.small).frame(width: 60)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hub.jobs[entry.id])
    }
}

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
                    Capsule().fill(.white.opacity(0.22)).frame(width: max(g.size.height, g.size.width * progress))
                        .animation(.easeOut(duration: 0.2), value: progress)
                }
            } else {
                Capsule().fill(.white.opacity(0.12))
            }
            HStack(spacing: 6) {
                if progress == nil { ProgressView().controlSize(.mini).tint(Theme.cream) }
                Text(label).monospacedDigit()
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

struct DetailView: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    let back: () -> Void

    var body: some View {
        let accent = Theme.accent(entry.accent)
        let release = hub.releases[entry.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button(action: back) {
                    Label("Toutes les apps", systemImage: "chevron.left")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                HStack(alignment: .center, spacing: 22) {
                    AppIcon(entry: entry, size: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.name).font(.system(size: 30, weight: .bold)).kerning(-0.6).foregroundStyle(Theme.cream)
                        Text(entry.tagline).font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
                        StatusLine(entry: entry).padding(.top, 4)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 10) {
                        ActionButton(entry: entry, large: true)
                        if hub.installed[entry.id] != nil {
                            Button("Afficher dans le Finder") { hub.revealInFinder(entry) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }

                Carousel(urls: gallery(release), accent: accent, symbol: entry.symbol)
                    .frame(height: 420)

                Text(entry.description)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let release {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Nouveautés").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.cream)
                            Text("v\(release.version)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.surfaceHi, in: Capsule())
                            if let d = release.date {
                                Text(d.formatted(date: .long, time: .omitted)).font(.system(size: 12.5)).foregroundStyle(Theme.faint)
                            }
                            Spacer()
                            Link(destination: release.page) {
                                Label("GitHub", systemImage: "arrow.up.right").font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(Theme.dim)
                        }
                        NotesView(text: release.notes, accent: accent)
                    }
                    .padding(20)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 46)
            .padding(.bottom, 36)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func gallery(_ r: Release?) -> [URL] {
        var seen = Set<URL>()
        return ((r?.images ?? []) + entry.screenshots).filter { seen.insert($0).inserted }
    }
}

// MARK: - Nouveautés d'une mise à jour

struct ChangelogSheet: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.dismiss) private var dismiss
    let entry: AppEntry

    var body: some View {
        let accent = Theme.accent(entry.accent)
        let release = hub.releases[entry.id]
        VStack(spacing: 0) {
            Carousel(urls: images(release), accent: accent, symbol: entry.symbol, corner: 0)
                .frame(height: 320)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.bg], startPoint: .top, endPoint: .bottom).frame(height: 70)
                        .allowsHitTesting(false)
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    AppIcon(entry: entry, size: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NOUVELLE VERSION")
                                .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.4))
                        Text("\(entry.name) \(release?.version ?? "")").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.cream)
                        if let i = hub.installed[entry.id] {
                            Text("Tu as la \(i.version)\(release?.date.map { " · publiée le \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.faint)
                        }
                    }
                    Spacer()
                }

                ScrollView {
                    NotesView(text: release?.notes ?? "", accent: accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 230)
                .scrollIndicators(.automatic)

                HStack {
                    Button("Plus tard") { close() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.surfaceHi, in: Capsule())
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    ActionButton(entry: entry, large: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .frame(width: 660)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onDisappear { hub.changelogClosed(entry) }
    }

    private func close() {
        dismiss()
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

struct MenuContent: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if hub.updates.isEmpty {
            Text(hub.checking ? "Recherche des mises à jour…" : "Toutes tes apps sont à jour")
        } else {
            ForEach(hub.updates) { e in
                Button("\(e.name) \(hub.releases[e.id]?.version ?? "") : voir les nouveautés") {
                    show()
                    hub.changelog = e
                }
            }
        }
        Divider()
        Button("Ouvrir OsaHUB") { show() }
        Button("Rechercher des mises à jour") { Task { await hub.refresh() } }
        Divider()
        Button("Quitter OsaHUB") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

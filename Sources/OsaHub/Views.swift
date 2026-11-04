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
                } else if hub.limitedUntil != nil || hub.offline {
                    EmptyView()
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
                        }
                        if hub.installed[entry.id] != nil {
                            Toggle("Mise à jour automatique", isOn: Binding(get: { hub.autoUpdate.contains(entry.id) }, set: { hub.setAutoUpdate(entry, $0) }))
                                .toggleStyle(.switch).controlSize(.mini)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.dim)
                                .help("Quand une nouvelle version sort, OsaHUB l'installe tout seul, si l'app n'est pas ouverte.")
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

                VersionHistory(entry: entry)
            }
            .padding(.horizontal, 36)
            .padding(.top, 96)
            .padding(.bottom, 36)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .onAppear { hub.loadHistory(entry) }
    }

    private func gallery(_ r: Release?) -> [URL] {
        var seen = Set<URL>()
        return ((r?.images ?? []) + entry.screenshots).filter { seen.insert($0).inserted }
    }
}

// MARK: - Historique des versions

struct VersionHistory: View {
    @EnvironmentObject private var hub: Hub
    let entry: AppEntry
    @State private var open: String?

    var body: some View {
        let list = (hub.history[entry.id] ?? []).filter { $0.version != hub.releases[entry.id]?.version }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Versions précédentes", detail: "pour revenir en arrière si une mise à jour te gêne")
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.version) { i, r in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        row(r)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func row(_ r: Release) -> some View {
        let expanded = open == r.version
        let current = hub.installed[entry.id]?.version == r.version
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.faint)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text("v\(r.version)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.surfaceHi, in: Capsule())
                Text(Notes.summary(r.notes) ?? r.title).font(.system(size: 12.5)).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer(minLength: 8)
                if let d = r.date { Text(d.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11.5)).foregroundStyle(Theme.faint) }
                if current {
                    Text("installée").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ok)
                } else if r.zip != nil && hub.jobs[entry.id] == nil {
                    Button("Installer") { hub.install(entry, version: r) }
                        .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream))
                        .help("Remplace la version installée par la \(r.version)")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { open = expanded ? nil : r.version } }
            if expanded {
                NotesView(text: r.notes, accent: Theme.cream)
                    .padding(.leading, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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

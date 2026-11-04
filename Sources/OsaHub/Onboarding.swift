import SwiftUI

// L'accueil des nouveaux utilisateurs (premier lancement, ou « Revoir l'accueil » dans le menu) :
//   1. Merci — la mascotte arrive et salue.
//   2. La suite — les apps tournent autour du hub et s'échangent des messages.
//   3. Entrer — choisir les apps à installer, deux réglages, puis on entre : le logo vivant
//      d'OsaHUB prend le relais (RootView).
// Noir et blanc seulement, comme OsaWallpaper. OSAHUB_ONBOARDING_STEP=0…2 ouvre une étape (captures).
struct OnboardingView: View {
    let done: () -> Void

    @EnvironmentObject private var hub: Hub
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Int(ProcessInfo.processInfo.environment["OSAHUB_ONBOARDING_STEP"] ?? "") ?? 0
    @State private var forward = true
    @State private var leaving = false
    // étape 3
    @State private var picked: Set<String>?
    @State private var atLogin = SMLogin.current
    @State private var autoSelf = true

    private let count = 3

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            OnboardingDust(reduceMotion: reduceMotion).opacity(leaving ? 0 : 1)
            Backdrop()

            VStack(spacing: 0) {
                topBar
                ZStack {
                    page(step)
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomBar
            }
            .padding(.horizontal, 48)
            .padding(.top, 30)
            .padding(.bottom, 34)
            .opacity(leaving ? 0 : 1)
            .blur(radius: leaving ? 12 : 0)
            .scaleEffect(leaving && !reduceMotion ? 1.03 : 1)
        }
        .onAppear {
            autoSelf = hub.autoSelf
            atLogin = hub.launchAtLogin
        }
    }

    // MARK: Pages

    @ViewBuilder private func page(_ i: Int) -> some View {
        switch i {
        case 0: OnboardingThanks(reduceMotion: reduceMotion)
        case 1: OnboardingSuite(entries: hub.entries, reduceMotion: reduceMotion)
        default: OnboardingSetup(picked: pickedBinding, atLogin: $atLogin, autoSelf: $autoSelf, reduceMotion: reduceMotion)
        }
    }

    /// Par défaut : toutes les apps disponibles et pas encore installées sont cochées.
    private var pickedBinding: Binding<Set<String>> {
        Binding(get: {
            picked ?? Set(hub.entries.filter { hub.installed[$0.id] == nil && !hub.isComingSoon($0) && $0.id != "osaweight" }.map(\.id))
        }, set: { picked = $0 })
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let dx: CGFloat = forward ? 60 : -60
        return .asymmetric(
            insertion: .modifier(active: OnboardingSlide(x: dx, opacity: 0, blur: 8), identity: OnboardingSlide(x: 0, opacity: 1, blur: 0)),
            removal: .modifier(active: OnboardingSlide(x: -dx, opacity: 0, blur: 8), identity: OnboardingSlide(x: 0, opacity: 1, blur: 0)))
    }

    // MARK: Barres

    private var topBar: some View {
        HStack {
            Lockup(size: 22)
                .opacity(0.9)
            Spacer()
            if step < count - 1 {
                Button("Passer") { go(count - 1) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .transition(.opacity)
            }
        }
        .frame(height: 30)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button {
                go(step - 1)
            } label: {
                Label("Retour", systemImage: "chevron.left")
            }
            .buttonStyle(PillStyle(fill: Theme.surfaceHi, text: Theme.cream, large: true))
            .keyboardShortcut(.leftArrow, modifiers: [])
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0)

            Spacer()
            OnboardingDots(count: count, current: step) { go($0) }
            Spacer()

            if step < count - 1 {
                Button {
                    go(step + 1)
                } label: {
                    HStack(spacing: 6) { Text("Continuer"); Image(systemName: "chevron.right") }
                }
                .buttonStyle(PillStyle(large: true))
                .keyboardShortcut(.defaultAction)
            } else {
                Button(action: enter) {
                    HStack(spacing: 6) { Text(enterTitle).contentTransition(.numericText()); Image(systemName: "arrow.right") }
                }
                .buttonStyle(PillStyle(large: true))
                .keyboardShortcut(.defaultAction)
            }
            // → avance aussi
            Button("") { if step < count - 1 { go(step + 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .frame(width: 0, height: 0).opacity(0)
        }
        .animation(.easeOut(duration: 0.2), value: step)
    }

    private var enterTitle: String {
        let n = pickedBinding.wrappedValue.count
        return n == 0 ? "Entrer dans OsaHUB" : "Installer \(n) app\(n > 1 ? "s" : "") et entrer"
    }

    // MARK: Actions

    private func go(_ i: Int) {
        let target = min(max(0, i), count - 1)
        guard target != step else { return }
        forward = target > step
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.88)) { step = target }
    }

    private func enter() {
        let chosen = hub.entries.filter { pickedBinding.wrappedValue.contains($0.id) && hub.installed[$0.id] == nil }
        if atLogin != hub.launchAtLogin { hub.setLaunchAtLogin(atLogin) }
        if autoSelf != hub.autoSelf { hub.setAutoSelf(autoSelf) }
        for e in chosen { hub.installWhenReady(e) }
        withAnimation(.easeIn(duration: 0.35)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done() }
    }
}

import ServiceManagement

private enum SMLogin {
    static var current: Bool { SMAppService.mainApp.status == .enabled }
}

extension Hub {
    /// Installe dès que la dernière version est connue (au premier lancement, la vérification
    /// peut ne pas être finie) ; abandonne au bout d'une minute.
    func installWhenReady(_ e: AppEntry) {
        Task { @MainActor in
            for _ in 0..<60 {
                if releases[e.id]?.zip != nil { install(e); return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - Transition de page

private struct OnboardingSlide: ViewModifier {
    let x: CGFloat
    let opacity: Double
    let blur: CGFloat
    func body(content: Content) -> some View {
        content.offset(x: x).opacity(opacity).blur(radius: blur)
    }
}

// MARK: - Apparition décalée

/// Fait apparaître un élément (monte de 14 pt, se défloute) après `delay`.
private struct OnboardingReveal: ViewModifier {
    let delay: Double
    let reduceMotion: Bool
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.7, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

private extension View {
    func reveal(_ delay: Double, _ reduceMotion: Bool) -> some View { modifier(OnboardingReveal(delay: delay, reduceMotion: reduceMotion)) }
}

// MARK: - 1. Merci

private struct OnboardingThanks: View {
    let reduceMotion: Bool
    @State private var arrived = false
    @State private var hop = 0
    @State private var arms: Mascot.Arms = .rest

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // un halo qui respire derrière la mascotte
                Circle().fill(.white).frame(width: 260, height: 260).blur(radius: 90).opacity(arrived ? 0.07 : 0)
                Mascot(mood: .happy, arms: arms, size: 120, hop: hop)
                    .scaleEffect(arrived || reduceMotion ? 1 : 0.7)
                    .offset(y: arrived || reduceMotion ? 0 : 30)
                    .opacity(arrived ? 1 : 0)
                    .onTapGesture { hop += 1; wave() }
                    .help("Coucou !")
            }
            .frame(height: 210)

            VStack(spacing: 14) {
                OnboardingWords(text: "Merci d’utiliser la suite Osa.", size: 44, start: 0.45, reduceMotion: reduceMotion)
                Text("Ça compte vraiment. Ces apps sont faites une par une, avec soin, pour que ton Mac soit un peu plus vivant chaque jour.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 520)
                    .reveal(1.15, reduceMotion)
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold))
                    Text("OsaLabs")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .padding(.top, 10)
                .reveal(1.45, reduceMotion)
            }
        }
        .offset(y: -10)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.6, dampingFraction: 0.62).delay(0.1)) { arrived = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { if !reduceMotion { hop += 1 }; wave() }
        }
    }

    private func wave() {
        arms = .wave
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { arms = .rest }
    }
}

/// Un titre qui arrive mot par mot (chaque mot monte et se défloute, 60 ms d'écart).
private struct OnboardingWords: View {
    let text: String
    var size: CGFloat
    var start: Double = 0
    let reduceMotion: Bool
    @State private var shown = false

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        HStack(spacing: size * 0.24) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                Text(w)
                    .font(Theme.title(size))
                    .kerning(-size * 0.02)
                    .foregroundStyle(Theme.cream)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : size * 0.35)
                    .blur(radius: shown || reduceMotion ? 0 : 8)
                    .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.6, dampingFraction: 0.82).delay(start + Double(i) * 0.06), value: shown)
            }
        }
        .fixedSize()
        .onAppear { shown = true }
    }
}

// MARK: - 2. La suite

private struct OnboardingSuite: View {
    let entries: [AppEntry]
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                OnboardingWords(text: "Une suite, pas juste des apps.", size: 34, start: 0.05, reduceMotion: reduceMotion)
                Text("Chaque app fait une chose, bien. Ensemble, elles en font plus.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .reveal(0.4, reduceMotion)
            }
            OnboardingOrbit(entries: entries, reduceMotion: reduceMotion)
                .frame(height: 250)
                .reveal(0.25, reduceMotion)
            HStack(alignment: .top, spacing: 14) {
                pillar("macwindow", "Natives et légères",
                       "Du Swift pur, pensé pour macOS. Rien ne tourne pour rien.", 0.7)
                pillar("arrow.left.arrow.right", "Elles se parlent",
                       "OsaWallpaper se range dans le menu d’OsaHUB. OsaNotch partage ton écran ou ta musique avec tes amis.", 0.8)
                pillar("arrow.triangle.2.circlepath", "Toujours à jour",
                       "OsaHUB installe et met à jour toute la suite, lui compris. Une seule mascotte dans ta barre des menus.", 0.9)
            }
            .frame(maxWidth: 860)
        }
    }

    private func pillar(_ symbol: String, _ title: String, _ text: String, _ delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.cream)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.surfaceHi))
            Text(title).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.cream)
            Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.dim).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .reveal(delay, reduceMotion)
    }
}

/// Le hub au centre, les apps en orbite lente reliées par des fils où passent des messages.
private struct OnboardingOrbit: View {
    let entries: [AppEntry]
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = reduceMotion ? 3 : tl.date.timeIntervalSince(start)
            GeometryReader { g in
                let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
                let rx = min(g.size.width * 0.32, 300), ry = g.size.height * 0.36
                let n = max(entries.count, 1)
                // arrivée : les apps partent du centre et rejoignent leur orbite
                let gather = Ease.outCubic(Ease.progress(t, 0.2, 1.1))
                let spin = t * 0.12
                let points: [CGPoint] = (0..<n).map { i in
                    let a = spin + Double(i) / Double(n) * 2 * .pi - .pi / 2
                    return CGPoint(x: c.x + CGFloat(cos(a)) * rx * gather, y: c.y + CGFloat(sin(a)) * ry * gather)
                }
                ZStack {
                    // ellipse de l'orbite
                    Ellipse().stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                        .frame(width: rx * 2, height: ry * 2).position(c).opacity(gather)
                    // fils + messages qui voyagent
                    Canvas { ctx, _ in
                        for (i, p) in points.enumerated() {
                            var line = Path(); line.move(to: c); line.addLine(to: p)
                            ctx.stroke(line, with: .color(.white.opacity(0.07 * gather)), lineWidth: 1)
                            // un point par fil, aller puis retour, décalé selon l'app
                            let phase = (t * 0.45 + Double(i) * 0.37).truncatingRemainder(dividingBy: 2)
                            let k = phase < 1 ? phase : 2 - phase
                            let e = Ease.inOutCubic(k)
                            let q = CGPoint(x: c.x + (p.x - c.x) * e, y: c.y + (p.y - c.y) * e)
                            let r: CGFloat = 2.6
                            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                                     with: .color(.white.opacity(0.75 * gather)))
                        }
                    }
                    // le hub
                    ZStack {
                        Circle().fill(.white).frame(width: 150, height: 150).blur(radius: 50).opacity(0.06 + 0.03 * sin(t * 1.6))
                        HubMark(size: 64,
                                appear: (0..<4).map { Ease.spring(Ease.progress(t, 0.05 + Double($0) * 0.07, 0.75)) },
                                glow: (0..<4).map { i in 0.25 * Ease.bump((t + Double(i) * 0.45).truncatingRemainder(dividingBy: 2.4), 0, 0.9) })
                    }
                    .position(c)
                    // les apps
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                        VStack(spacing: 6) {
                            AppIcon(entry: e, size: 52)
                            Text(e.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                        }
                        .scaleEffect(0.6 + 0.4 * gather)
                        .opacity(gather)
                        .position(x: points[i].x, y: points[i].y + 6)
                    }
                }
            }
        }
    }
}

// MARK: - 3. Entrer

private struct OnboardingSetup: View {
    @Binding var picked: Set<String>
    @Binding var atLogin: Bool
    @Binding var autoSelf: Bool
    let reduceMotion: Bool
    @EnvironmentObject private var hub: Hub

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                OnboardingWords(text: "Prépare ton Mac.", size: 34, start: 0.05, reduceMotion: reduceMotion)
                Text("Coche les apps à installer maintenant. Tu pourras en ajouter ou en retirer quand tu veux.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .reveal(0.3, reduceMotion)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(Array(hub.entries.enumerated()), id: \.element.id) { i, e in
                    OnboardingAppChoice(entry: e,
                                        installed: hub.installed[e.id] != nil,
                                        soon: hub.isComingSoon(e) || e.id == "osaweight" && hub.releases[e.id]?.zip == nil,
                                        on: picked.contains(e.id)) {
                        if picked.contains(e.id) { picked.remove(e.id) } else { picked.insert(e.id) }
                    }
                    .reveal(0.35 + Double(i) * 0.06, reduceMotion)
                }
            }
            .frame(maxWidth: 820)

            HStack(spacing: 14) {
                toggle("Ouvrir OsaHUB à la connexion", "Il veille sur tes apps depuis la barre des menus.", $atLogin)
                toggle("Mettre à jour OsaHUB tout seul", "Quand sa fenêtre est fermée, sans te déranger.", $autoSelf)
            }
            .frame(maxWidth: 820)
            .reveal(0.65, reduceMotion)
        }
    }

    private func toggle(_ title: String, _ sub: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.cream)
                Text(sub).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: value).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

private struct OnboardingAppChoice: View {
    let entry: AppEntry
    let installed: Bool
    let soon: Bool
    let on: Bool
    let toggle: () -> Void
    @State private var hover = false

    private var enabled: Bool { !installed && !soon }
    private var checked: Bool { installed || (on && enabled) }

    var body: some View {
        Button(action: { if enabled { toggle() } }) {
            HStack(spacing: 14) {
                AppIcon(entry: entry, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Theme.cream)
                    Text(entry.tagline).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(2)
                }
                Spacer(minLength: 6)
                if installed {
                    Text("Installée").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ok)
                } else if soon {
                    Text("Bientôt").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                } else {
                    ZStack {
                        Circle().strokeBorder(.white.opacity(checked ? 0 : 0.25), lineWidth: 1.5)
                        Circle().fill(Theme.cream).scaleEffect(checked ? 1 : 0.5).opacity(checked ? 1 : 0)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.ink)
                            .scaleEffect(checked ? 1 : 0.4).opacity(checked ? 1 : 0)
                    }
                    .frame(width: 22, height: 22)
                    .animation(.spring(response: 0.3, dampingFraction: 0.62), value: checked)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(checked && enabled ? Theme.surfaceHi : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(checked && enabled ? 0.22 : (hover && enabled ? 0.14 : 0.08)), lineWidth: 1))
            .opacity(soon ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(OnboardingPress())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

private struct OnboardingPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Pagination

private struct OnboardingDots: View {
    let count: Int
    let current: Int
    let go: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == current ? 0.9 : 0.22))
                    .frame(width: i == current ? 22 : 7, height: 7)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { go(i) }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }
}

// MARK: - Poussière

/// Des points blancs à peine visibles qui dérivent lentement (fond vivant, très discret).
private struct OnboardingDust: View {
    let reduceMotion: Bool
    @State private var start = Date()
    private static let seeds: [(x: Double, y: Double, r: Double, s: Double, p: Double)] = {
        var g = SeededRandom(seed: 7)
        return (0..<70).map { _ in (g.next(), g.next(), 0.6 + g.next() * 1.6, 0.004 + g.next() * 0.012, g.next() * 6.28) }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                for d in Self.seeds {
                    let y = (d.y - t * d.s).truncatingRemainder(dividingBy: 1)
                    let yy = (y < 0 ? y + 1 : y) * size.height
                    let x = d.x * size.width + CGFloat(sin(t * 0.3 + d.p)) * 12
                    let a = 0.05 + 0.1 * (0.5 + 0.5 * sin(t * 0.8 + d.p))
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: yy, width: d.r * 2, height: d.r * 2)), with: .color(.white.opacity(a)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

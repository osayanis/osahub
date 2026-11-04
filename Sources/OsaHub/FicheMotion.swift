import SwiftUI
import Observation

// Le mouvement de la fiche d'une app : défilement suivi, arrivées décalées, coche de succès.
// Avec « Réduire les animations », tout devient de simples fondus, sans déplacement.

enum FicheMotion {
    /// Ressort des arrivées : rapide au départ, posé à la fin.
    static let enter = Animation.spring(response: 0.55, dampingFraction: 0.88)
    /// Ressort des changements d'état (dépliage, bascule).
    static let state = Animation.spring(response: 0.36, dampingFraction: 0.86)

    static func enter(_ reduce: Bool, delay: Double = 0) -> Animation {
        (reduce ? Animation.easeOut(duration: 0.2) : enter).delay(delay)
    }

    static func state(_ reduce: Bool) -> Animation {
        reduce ? .easeOut(duration: 0.18) : state
    }
}

/// Où en est le défilement de la fiche. @Observable : seules les vues qui lisent `scrolled`
/// se redessinent à chaque image, pas la fiche entière.
@Observable
final class FicheScroll {
    var y: CGFloat = 0
    var rest: CGFloat?
    /// Points défilés depuis le haut (0 au repos).
    var scrolled: CGFloat { max(0, (rest ?? y) - y) }
}

/// Arrivée d'une section : monte de quelques points, sort du flou. Une seule fois.
struct FicheReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 14)
            .blur(radius: shown || reduce ? 0 : 5)
            .onAppear {
                withAnimation(FicheMotion.enter(reduce, delay: 0.05 + Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    func ficheReveal(_ index: Int) -> some View { modifier(FicheReveal(index: index)) }
}

/// Fondu avec un léger flou : l'œil voit une seule image qui change, pas deux qui se croisent.
struct FicheBlurFade: ViewModifier {
    let active: Bool
    var scale: CGFloat = 1
    var y: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 6 : 0)
            .scaleEffect(active ? scale : 1)
            .offset(y: active ? y : 0)
    }
}

extension AnyTransition {
    static func ficheBlur(scale: CGFloat = 1, y: CGFloat = 0) -> AnyTransition {
        .modifier(active: FicheBlurFade(active: true, scale: scale, y: y), identity: FicheBlurFade(active: false))
    }
}

/// La coche de succès : le rond puis le trait se dessinent.
struct FicheCheck: View {
    var size: CGFloat = 16
    var color: Color = Theme.ok
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: drawn).stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            FicheCheckShape().trim(from: 0, to: max(0, drawn * 1.6 - 0.6))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round, lineJoin: .round))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduce { drawn = 1 } else { withAnimation(.easeOut(duration: 0.5).delay(0.05)) { drawn = 1 } }
        }
    }
}

private struct FicheCheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.05))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY - r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.12))
        return p
    }
}

/// Un reflet qui traverse une barre pendant un travail en cours (mouvement constant : linéaire).
struct FicheSheen: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { g in
            if !reduce {
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.16), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(40, g.size.width * 0.45))
                    .offset(x: phase * g.size.width)
                    .onAppear {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.2 }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Les notes de version, bloc par bloc, qui arrivent en décalé (feuille des nouveautés).
struct FicheNotes: View {
    let text: String
    var startDelay: Double = 0.25
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let blocks = Notes.blocks(text)
        VStack(alignment: .leading, spacing: 11) {
            if blocks.isEmpty {
                Text("Pas de notes pour cette version.").foregroundStyle(Theme.faint)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                block(b)
                    .modifier(FicheStagger(delay: startDelay + Double(min(i, 12)) * 0.045))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.75))
        .lineSpacing(3)
        .tint(Theme.cream)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func block(_ b: Notes.Block) -> some View {
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

private struct FicheStagger: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown || reduce ? 0 : -8)
            .onAppear { withAnimation(FicheMotion.enter(reduce, delay: delay)) { shown = true } }
    }
}

/// Retour au toucher : léger enfoncement de tout ce qui se clique.
struct FichePress: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

import SwiftUI

// Les couleurs de la suite Osa.
enum Theme {
    // Sobre comme OsaWallpaper : noir, blanc à différentes opacités, la couleur seulement pour un état.
    static let bg = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let surface = Color.white.opacity(0.05)
    static let surfaceHi = Color.white.opacity(0.08)
    static let line = Color.white.opacity(0.08)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.38)
    static let cream = Color.white.opacity(0.95)
    static let ink = Color.black
    static let ok = Color.green
    static let red = Color(red: 1, green: 0.42, blue: 0.45)

    /// Le « HUB » du logo : du blanc qui s'éteint doucement.
    static let hubGradient = LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.36)], startPoint: .leading, endPoint: .trailing)

    static func title(_ s: CGFloat) -> Font { .system(size: s, weight: .bold) }

    /// Une seule teinte pour toutes les apps : le blanc (le champ « accent » du catalogue est gardé
    /// pour plus tard, sans effet sur l'interface).
    static func accent(_ name: String) -> Color { cream }
}

/// Le logo texte : « Osa » crème, « HUB » en dégradé.
struct HubLogo: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(spacing: size * 0.03) {
            Text("Osa").foregroundStyle(Theme.cream)
            Text("HUB").foregroundStyle(Theme.hubGradient)
        }
        .font(Theme.title(size))
        .kerning(-size * 0.02)
    }
}

/// Une lueur blanche à peine visible en haut, comme la lumière d'OsaWallpaper (rien d'animé).
struct Backdrop: View {
    var body: some View {
        VStack {
            Ellipse().fill(.white).frame(width: 900, height: 360).blur(radius: 160).opacity(0.05)
                .offset(y: -220)
            Spacer()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Bouton-pilule de la suite.
struct PillStyle: ButtonStyle {
    var fill: Color = Theme.cream
    var text: Color = Theme.ink
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 12.5, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, large ? 22 : 15)
            .padding(.vertical, large ? 10 : 7)
            .background(Capsule().fill(fill))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

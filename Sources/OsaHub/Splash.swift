import SwiftUI

/// L'ouverture : « OsaHUB » en motion design.
/// Un point s'allume et éclate en onde, « Osa » monte du flou lettre par lettre, « HUB » bascule
/// à sa place, un reflet traverse le mot, un trait se trace, puis tout s'efface vers l'app.
/// Noir et blanc seulement, comme OsaWallpaper.
/// Un clic passe l'animation.
struct Splash: View {
    let finish: () -> Void

    @State private var step = 0
    @State private var shine: CGFloat = -1.6
    @State private var ended = false

    private let osa = Array("Osa")
    private let hub = Array("HUB")
    private let size: CGFloat = 92

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            // une lueur blanche, discrète, qui s'allume derrière le mot
            Ellipse().fill(.white).frame(width: 720, height: 300).blur(radius: 150)
                .opacity(step >= 3 ? 0.07 : (step >= 2 ? 0.04 : 0)).scaleEffect(step >= 2 ? 1 : 0.4)

            // le point, puis son onde
            Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1)
                .frame(width: step >= 2 ? 620 : 10, height: step >= 2 ? 620 : 10)
                .opacity(step == 1 ? 1 : 0)
            Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                .frame(width: step >= 2 ? 900 : 10, height: step >= 2 ? 900 : 10)
                .opacity(step == 1 ? 1 : 0)
            Circle().fill(Theme.cream).frame(width: 12, height: 12)
                .scaleEffect(step == 1 ? 1 : 0.01)
                .opacity(step == 1 ? 1 : 0)
                .shadow(color: .white.opacity(0.6), radius: 10)

            VStack(spacing: 26) {
                word
                    .overlay { shineLayer.mask(word) }
                Capsule().fill(.white.opacity(0.25))
                    .frame(width: step >= 4 ? 240 : 0, height: 2)
                    .opacity(step >= 4 ? 1 : 0)
                Text("TOUTES LES APPS OSALABS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(step >= 5 ? 3.2 : 12)
                    .foregroundStyle(.white.opacity(0.4))
                    .opacity(step >= 5 ? 1 : 0)
            }
            .scaleEffect(step >= 6 ? 1.1 : 1)
            .blur(radius: step >= 6 ? 18 : 0)
            .opacity(step >= 6 ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { end() }
        .task { await play() }
    }

    private var word: some View {
        HStack(spacing: 0) {
            ForEach(osa.indices, id: \.self) { i in
                Text(String(osa[i]))
                    .foregroundStyle(Theme.cream)
                    .opacity(step >= 2 ? 1 : 0)
                    .offset(y: step >= 2 ? 0 : size * 0.6)
                    .blur(radius: step >= 2 ? 0 : 14)
                    .animation(.spring(response: 0.72, dampingFraction: 0.66).delay(Double(i) * 0.08), value: step >= 2)
            }
            Color.clear.frame(width: size * 0.05, height: 1)
            hubLetters(fill: false)
                .hidden()
                .overlay { Theme.hubGradient.mask(hubLetters(fill: true)) }
        }
        .font(Theme.title(size))
        .kerning(-size * 0.025)
    }

    private func hubLetters(fill: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(hub.indices, id: \.self) { i in
                Text(String(hub[i]))
                    .opacity(step >= 3 ? 1 : 0)
                    .rotation3DEffect(.degrees(step >= 3 ? 0 : -95), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55)
                    .offset(y: step >= 3 ? 0 : -size * 0.15)
                    .scaleEffect(step >= 3 ? 1 : 0.8, anchor: .bottom)
                    .animation(.spring(response: 0.62, dampingFraction: 0.62).delay(Double(i) * 0.09), value: step >= 3)
            }
        }
    }

    private var shineLayer: some View {
        GeometryReader { g in
            LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 110, height: g.size.height * 2)
                .rotationEffect(.degrees(18))
                .offset(x: g.size.width / 2 - 55 + shine * g.size.width * 0.6, y: -g.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private func play() async {
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { step = 1 }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(.easeOut(duration: 1.15)) { step = 2 }
        try? await Task.sleep(for: .milliseconds(430))
        withAnimation(.easeOut(duration: 0.9)) { step = 3 }
        try? await Task.sleep(for: .milliseconds(560))
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { step = 4 }
        withAnimation(.easeInOut(duration: 1.0)) { shine = 1.6 }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(.easeOut(duration: 0.8)) { step = 5 }
        try? await Task.sleep(for: .milliseconds(1050))
        end()
    }

    private func end() {
        guard !ended else { return }
        ended = true
        withAnimation(.easeIn(duration: 0.42)) { step = 6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { finish() }
    }
}

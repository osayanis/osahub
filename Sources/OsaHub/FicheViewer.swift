import SwiftUI

/// Les captures en grand, par-dessus la fiche : flèches (ou ← →), vignettes, Échap pour fermer.
/// L'index est celui du carrousel : on retrouve la même capture en refermant.
struct FicheViewer: View {
    let urls: [URL]
    @Binding var index: Int
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    var body: some View {
        ZStack {
            Theme.bg.opacity(0.97)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            VStack(spacing: 18) {
                ZStack {
                    ForEach(urls.indices, id: \.self) { i in
                        if i == current {
                            RemoteImage(url: urls[i], mode: .fit) { ProgressView().controlSize(.small) }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
                                .transition(.ficheBlur())
                        }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: current)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) { arrow("chevron.left", -1) }
                .overlay(alignment: .trailing) { arrow("chevron.right", 1) }
                .scaleEffect(shown || reduce ? 1 : 0.96)
                .blur(radius: shown || reduce ? 0 : 8)

                bottomBar
            }
            .padding(.top, 92)
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(reduce ? .easeOut(duration: 0.18) : .easeOut(duration: 0.28)) { shown = true } }
    }

    private var current: Int { urls.isEmpty ? 0 : min(max(0, index), urls.count - 1) }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Text("\(current + 1) / \(urls.count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.dim)
                .frame(width: 56, alignment: .leading)
            Spacer(minLength: 0)
            if urls.count > 1 {
                HStack(spacing: 8) {
                    ForEach(urls.indices, id: \.self) { i in
                        thumb(i)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Label("Fermer", systemImage: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.surfaceHi, in: Capsule())
            }
            .buttonStyle(FichePress())
            .frame(width: 96, alignment: .trailing)
            .help("Fermer (Échap)")
        }
    }

    private func thumb(_ i: Int) -> some View {
        let active = i == current
        return Button { index = i } label: {
            Color.clear
                .frame(width: 64, height: 40)
                .overlay { RemoteImage(url: urls[i], mode: .fill) { Theme.surface } }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(active ? Theme.cream : .white.opacity(0.1), lineWidth: active ? 1.5 : 1))
                .opacity(active ? 1 : 0.5)
                .animation(.easeOut(duration: 0.15), value: active)
        }
        .buttonStyle(FichePress(scale: 0.94))
    }

    private func arrow(_ name: String, _ d: Int) -> some View {
        Button { step(d) } label: {
            Image(systemName: name).font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.cream)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
        }
        .buttonStyle(FichePress(scale: 0.92))
        .opacity(urls.count > 1 ? 1 : 0)
        .disabled(urls.count < 2)
    }

    private func step(_ d: Int) {
        guard !urls.isEmpty else { return }
        index = (current + d + urls.count) % urls.count
    }
}

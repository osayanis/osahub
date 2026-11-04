import SwiftUI

/// L'accueil des nouveaux utilisateurs (premier lancement, ou « Revoir l'accueil ») :
/// 1. merci d'utiliser la suite Osa, 2. le concept de la suite, 3. entrer dans OsaHUB.
/// `done` est appelé à la fin : le logo vivant prend alors le relais.
struct OnboardingView: View {
    let done: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Merci d’utiliser la suite Osa").font(Theme.title(34)).foregroundStyle(Theme.cream)
            Button("Entrer dans OsaHUB", action: done).buttonStyle(PillStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

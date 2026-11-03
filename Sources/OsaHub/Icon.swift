import SwiftUI
import AppKit

/// L'icône : la mascotte OsaLabs devant une grille d'apps (la dernière tuile porte la flèche
/// de téléchargement), sur le même fond sombre que les autres apps Osa.
struct IconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.26), Color(red: 0.06, green: 0.06, blue: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 340))
                .frame(width: 700, height: 700).offset(y: 30)
            // la grille d'apps, derrière la mascotte
            VStack(spacing: 22) {
                HStack(spacing: 22) { tile(0.95); tile(0.7) }
                HStack(spacing: 22) { tile(0.7); tile(0.45, arrow: true) }
            }
            .rotationEffect(.degrees(-10))
            .offset(x: 150, y: -140)
            Mascot(mood: .happy, size: 430).offset(x: -60, y: 125)
        }
        .frame(width: 1024, height: 1024)
    }

    private func tile(_ o: Double, arrow: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
            .fill(.white.opacity(o))
            .frame(width: 128, height: 128)
            .overlay {
                if arrow { Image(systemName: "arrow.down").font(.system(size: 70, weight: .black)).foregroundStyle(.black.opacity(0.75)) }
            }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    @MainActor static func export(to dir: URL) throws {
        let r = ImageRenderer(content: IconArt())
        r.scale = 1
        guard let cg = r.cgImage else { throw Failure("Rendu de l'icône impossible.") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                           (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
            let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("icon_\(name).png"))
        }
    }
}

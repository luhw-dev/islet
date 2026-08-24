import AppKit
import SwiftUI

/// Duas cores tiradas da capa: uma para o waveform, outra para o progresso.
struct ArtworkPalette: Equatable {
    var primary: NSColor
    var secondary: NSColor

    var primaryColor: Color { Color(nsColor: primary) }
    var secondaryColor: Color { Color(nsColor: secondary) }

    static let fallback = ArtworkPalette(
        primary: NSColor(white: 0.92, alpha: 1),
        secondary: NSColor(white: 0.75, alpha: 1)
    )
}

/// Histograma de matiz sobre uma miniatura da capa.
///
/// Não vale usar a cor média (dá sempre um cinza lamacento): o que a gente quer
/// é a matiz com mais peso de saturação, e depois uma segunda bem distante dela.
enum PaletteExtractor {
    private static let amostra = 24
    private static let faixas = 12

    static func palette(from image: NSImage) -> ArtworkPalette {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .fallback
        }

        let lado = amostra
        var pixels = [UInt8](repeating: 0, count: lado * lado * 4)
        guard let contexto = CGContext(
            data: &pixels,
            width: lado,
            height: lado,
            bitsPerComponent: 8,
            bytesPerRow: lado * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .fallback }

        contexto.draw(cgImage, in: CGRect(x: 0, y: 0, width: lado, height: lado))

        var peso = [Double](repeating: 0, count: faixas)
        var soma = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: faixas)

        for indice in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[indice]) / 255
            let g = Double(pixels[indice + 1]) / 255
            let b = Double(pixels[indice + 2]) / 255
            let (h, s, v) = hsb(r: r, g: g, b: b)

            // Preto de fundo e cinza de textura só sujam a conta.
            guard v > 0.15, s > 0.2 else { continue }

            let faixa = min(faixas - 1, Int(h * Double(faixas)))
            let w = s * v
            peso[faixa] += w
            soma[faixa].r += r * w
            soma[faixa].g += g * w
            soma[faixa].b += b * w
        }

        let ordenadas = peso.indices.sorted { peso[$0] > peso[$1] }
        guard let melhor = ordenadas.first, peso[melhor] > 0 else { return .fallback }

        let primaria = realce(media(soma[melhor], peso[melhor]))

        // Uma segunda cor só vale se for outra matiz E tiver peso de verdade.
        // Sem esse piso, uma sombra colorida qualquer virava a cor do progresso.
        let alternativa = ordenadas.dropFirst().first { faixa in
            peso[faixa] >= peso[melhor] * 0.25 && distanciaDeFaixa(faixa, melhor) >= 2
        }
        let secundaria = alternativa.map { realce(media(soma[$0], peso[$0])) }
            ?? clareia(primaria)

        return ArtworkPalette(primary: primaria, secondary: secundaria)
    }

    private static func media(_ soma: (r: Double, g: Double, b: Double), _ peso: Double) -> NSColor {
        NSColor(
            srgbRed: CGFloat(soma.r / peso),
            green: CGFloat(soma.g / peso),
            blue: CGFloat(soma.b / peso),
            alpha: 1
        )
    }

    /// Sobre fundo preto, cor lavada some. Garante um piso de saturação e brilho.
    private static func realce(_ cor: NSColor) -> NSColor {
        guard let rgb = cor.usingColorSpace(.sRGB) else { return cor }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: max(s, 0.5), brightness: max(b, 0.78), alpha: 1)
    }

    /// Variação clara da própria cor, para quando a capa é monocromática.
    private static func clareia(_ cor: NSColor) -> NSColor {
        guard let rgb = cor.usingColorSpace(.sRGB) else { return cor }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s * 0.45, brightness: min(1, b + 0.15), alpha: 1)
    }

    private static func distanciaDeFaixa(_ a: Int, _ b: Int) -> Int {
        let bruta = abs(a - b)
        return min(bruta, faixas - bruta)
    }

    private static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maximo = max(r, g, b)
        let minimo = min(r, g, b)
        let delta = maximo - minimo
        var h = 0.0
        if delta > 0 {
            if maximo == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximo == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maximo == 0 ? 0 : delta / maximo, maximo)
    }
}

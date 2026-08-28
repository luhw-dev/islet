import SwiftUI

/// As marcas do Claude e do Codex desenhadas como `Path`.
///
/// O app não embute recursos (é um binário só, sem asset catalog), e um SF
/// Symbol parecido não é a logo — então os contornos vêm no código. Os dados
/// são do simple-icons (CC0), convertidos para um quadrado 0…1: a mesma
/// normalização nas duas é o que as deixa do mesmo tamanho óptico dentro do
/// anel. Arcos já vêm virados em cubicas, então o leitor abaixo só precisa
/// entender M, L, C e Z absolutos.
enum BrandGlyph {
    case claude
    case codex

    /// Acerto óptico: o sunburst do Claude preenche o quadrado, enquanto o nó
    /// da OpenAI é vazado e de traço fino — no mesmo tamanho ele parece menor.
    var opticalScale: CGFloat {
        switch self {
        case .claude: return 0.92
        case .codex: return 1.06
        }
    }

    /// Contorno dentro do quadrado unitário.
    var unitPath: Path {
        switch self {
        case .claude: return Self.claudePath
        case .codex: return Self.codexPath
        }
    }

    private static let claudePath = parse(claudeData)
    private static let codexPath = parse(codexData)

    /// Leitor mínimo do subconjunto de SVG que o conversor emite.
    private static func parse(_ data: String) -> Path {
        var path = Path()
        var numeros = data.split(whereSeparator: \.isWhitespace).makeIterator()
        var pendente: [CGFloat] = []

        func proximo() -> Substring? { numeros.next() }

        var token = proximo()
        while let atual = token {
            switch atual {
            case "M", "L", "C", "Z":
                let comando = atual
                pendente.removeAll(keepingCapacity: true)
                token = proximo()
                while let valor = token, let numero = Double(valor) {
                    pendente.append(CGFloat(numero))
                    token = proximo()
                }
                aplica(comando, pendente, to: &path)
            default:
                // Lixo no meio dos dados: melhor parar do que desenhar torto.
                return path
            }
        }
        return path
    }

    private static func aplica(_ comando: Substring, _ v: [CGFloat], to path: inout Path) {
        switch comando {
        case "M" where v.count >= 2:
            path.move(to: CGPoint(x: v[0], y: v[1]))
        case "L" where v.count >= 2:
            path.addLine(to: CGPoint(x: v[0], y: v[1]))
        case "C" where v.count >= 6:
            path.addCurve(
                to: CGPoint(x: v[4], y: v[5]),
                control1: CGPoint(x: v[0], y: v[1]),
                control2: CGPoint(x: v[2], y: v[3]))
        case "Z":
            path.closeSubpath()
        default:
            break
        }
    }

    private static let claudeData = """
        M 0.1964 0.6648 L 0.3930 0.5545 L 0.3963 0.5449 L 0.3930 0.5396 L 0.3834
        0.5396 L 0.3505 0.5376 L 0.2382 0.5345 L 0.1408 0.5305 L 0.0464 0.5254 L
        0.0226 0.5204 L 0.0004 0.4910 L 0.0027 0.4763 L 0.0226 0.4629 L 0.0512
        0.4655 L 0.1145 0.4698 L 0.2093 0.4763 L 0.2781 0.4804 L 0.3801 0.4910 L
        0.3963 0.4910 L 0.3986 0.4844 L 0.3930 0.4804 L 0.3887 0.4763 L 0.2905
        0.4098 L 0.1843 0.3395 L 0.1286 0.2990 L 0.0985 0.2785 L 0.0834 0.2593 L
        0.0768 0.2173 L 0.1041 0.1872 L 0.1408 0.1897 L 0.1501 0.1923 L 0.1873
        0.2208 L 0.2668 0.2823 L 0.3705 0.3587 L 0.3857 0.3714 L 0.3917 0.3671 L
        0.3925 0.3640 L 0.3857 0.3526 L 0.3292 0.2507 L 0.2690 0.1470 L 0.2422
        0.1040 L 0.2351 0.0782 C 0.2326 0.0675 0.2308 0.0587 0.2308 0.0478 L
        0.2620 0.0056 L 0.2792 0.0000 L 0.3206 0.0056 L 0.3381 0.0207 L 0.3639
        0.0797 L 0.4056 0.1725 L 0.4704 0.2988 L 0.4894 0.3362 L 0.4995 0.3709 L
        0.5033 0.3815 L 0.5099 0.3815 L 0.5099 0.3754 L 0.5152 0.3043 L 0.5250
        0.2171 L 0.5347 0.1047 L 0.5379 0.0731 L 0.5536 0.0352 L 0.5847 0.0147 L
        0.6090 0.0263 L 0.6290 0.0549 L 0.6262 0.0734 L 0.6143 0.1505 L 0.5911
        0.2714 L 0.5759 0.3524 L 0.5847 0.3524 L 0.5949 0.3423 L 0.6358 0.2879 L
        0.7047 0.2019 L 0.7350 0.1677 L 0.7704 0.1300 L 0.7932 0.1121 L 0.8362
        0.1121 L 0.8678 0.1591 L 0.8537 0.2077 L 0.8094 0.2639 L 0.7727 0.3114 L
        0.7201 0.3822 L 0.6872 0.4389 L 0.6902 0.4435 L 0.6981 0.4427 L 0.8170
        0.4174 L 0.8812 0.4058 L 0.9579 0.3926 L 0.9925 0.4088 L 0.9963 0.4252 L
        0.9827 0.4589 L 0.9007 0.4791 L 0.8046 0.4984 L 0.6614 0.5323 L 0.6596
        0.5335 L 0.6617 0.5361 L 0.7262 0.5421 L 0.7537 0.5436 L 0.8213 0.5436 L
        0.9470 0.5530 L 0.9799 0.5748 L 0.9996 0.6013 L 0.9963 0.6216 L 0.9457
        0.6474 L 0.8774 0.6312 L 0.7181 0.5932 L 0.6634 0.5796 L 0.6558 0.5796 L
        0.6558 0.5841 L 0.7014 0.6286 L 0.7848 0.7040 L 0.8893 0.8012 L 0.8946
        0.8252 L 0.8812 0.8442 L 0.8671 0.8421 L 0.7752 0.7731 L 0.7398 0.7420 L
        0.6596 0.6744 L 0.6543 0.6744 L 0.6543 0.6815 L 0.6728 0.7086 L 0.7704
        0.8553 L 0.7755 0.9003 L 0.7684 0.9150 L 0.7431 0.9239 L 0.7153 0.9188 L
        0.6581 0.8386 L 0.5992 0.7483 L 0.5516 0.6673 L 0.5458 0.6706 L 0.5177
        0.9729 L 0.5046 0.9884 L 0.4742 1.0000 L 0.4489 0.9808 L 0.4355 0.9497 L
        0.4489 0.8882 L 0.4651 0.8080 L 0.4782 0.7442 L 0.4901 0.6651 L 0.4972
        0.6388 L 0.4967 0.6370 L 0.4909 0.6377 L 0.4312 0.7197 L 0.3404 0.8424 L
        0.2685 0.9193 L 0.2513 0.9261 L 0.2215 0.9107 L 0.2243 0.8831 L 0.2410
        0.8586 L 0.3404 0.7321 L 0.4003 0.6537 L 0.4390 0.6084 L 0.4388 0.6018 L
        0.4365 0.6018 L 0.1724 0.7733 L 0.1253 0.7794 L 0.1051 0.7604 L 0.1076
        0.7293 L 0.1173 0.7192 L 0.1967 0.6646 Z
        """

    private static let codexData = """
        M 0.9284 0.4092 C 0.9510 0.3411 0.9432 0.2665 0.9069 0.2046 C 0.8524
        0.1096 0.7427 0.0608 0.6357 0.0838 C 0.5753 0.0166 0.4838 -0.0132 0.3955
        0.0055 C 0.3072 0.0241 0.2355 0.0884 0.2075 0.1742 C 0.1372 0.1887
        0.0765 0.2327 0.0410 0.2951 C -0.0142 0.3899 -0.0017 0.5094 0.0719
        0.5908 C 0.0492 0.6589 0.0570 0.7334 0.0932 0.7954 C 0.1478 0.8904
        0.2575 0.9392 0.3646 0.9162 C 0.4123 0.9699 0.4807 1.0004 0.5525 1.0000
        C 0.6622 1.0001 0.7595 0.9293 0.7930 0.8248 C 0.8633 0.8103 0.9240
        0.7663 0.9596 0.7039 C 1.0140 0.6093 1.0015 0.4904 0.9284 0.4092 Z M
        0.5525 0.9345 C 0.5087 0.9346 0.4663 0.9193 0.4326 0.8912 L 0.4386
        0.8878 L 0.6377 0.7729 C 0.6477 0.7670 0.6540 0.7562 0.6540 0.7445 L
        0.6540 0.4638 L 0.7382 0.5125 C 0.7390 0.5129 0.7396 0.5137 0.7398
        0.5147 L 0.7398 0.7473 C 0.7395 0.8506 0.6558 0.9343 0.5525 0.9345 Z M
        0.1500 0.7627 C 0.1280 0.7247 0.1201 0.6803 0.1277 0.6371 L 0.1336
        0.6406 L 0.3329 0.7556 C 0.3429 0.7615 0.3554 0.7615 0.3654 0.7556 L
        0.6089 0.6152 L 0.6089 0.7124 C 0.6088 0.7134 0.6083 0.7144 0.6075
        0.7150 L 0.4058 0.8313 C 0.3162 0.8829 0.2017 0.8522 0.1500 0.7627 Z M
        0.0975 0.3290 C 0.1196 0.2908 0.1546 0.2617 0.1961 0.2468 L 0.1961
        0.4833 C 0.1959 0.4950 0.2021 0.5058 0.2123 0.5115 L 0.4545 0.6513 L
        0.3704 0.7000 C 0.3694 0.7005 0.3683 0.7005 0.3674 0.7000 L 0.1661
        0.5839 C 0.0767 0.5320 0.0460 0.4176 0.0975 0.3280 Z M 0.7890 0.4896 L
        0.5460 0.3485 L 0.6300 0.3000 C 0.6309 0.2995 0.6320 0.2995 0.6329
        0.3000 L 0.8342 0.4163 C 0.8970 0.4525 0.9332 0.5218 0.9272 0.5941 C
        0.9212 0.6664 0.8740 0.7286 0.8060 0.7540 L 0.8060 0.5174 C 0.8056
        0.5058 0.7992 0.4953 0.7890 0.4896 Z M 0.8728 0.3637 L 0.8669 0.3601 L
        0.6680 0.2442 C 0.6579 0.2383 0.6454 0.2383 0.6353 0.2442 L 0.3920
        0.3846 L 0.3920 0.2874 C 0.3919 0.2864 0.3924 0.2854 0.3932 0.2848 L
        0.5945 0.1687 C 0.6575 0.1324 0.7357 0.1358 0.7953 0.1774 C 0.8549
        0.2190 0.8851 0.2913 0.8728 0.3629 Z M 0.3461 0.5360 L 0.2619 0.4875 C
        0.2611 0.4869 0.2605 0.4861 0.2604 0.4851 L 0.2604 0.2531 C 0.2604
        0.1804 0.3025 0.1144 0.3683 0.0836 C 0.4341 0.0527 0.5118 0.0627 0.5677
        0.1092 L 0.5618 0.1125 L 0.3627 0.2275 C 0.3526 0.2334 0.3464 0.2442
        0.3463 0.2558 Z M 0.3918 0.4374 L 0.5003 0.3749 L 0.6089 0.4374 L 0.6089
        0.5624 L 0.5006 0.6249 L 0.3920 0.5624 Z
        """
}

/// Desenha uma marca centralizada e quadrada dentro do espaço que receber.
struct BrandGlyphShape: Shape {
    let glyph: BrandGlyph

    func path(in rect: CGRect) -> Path {
        let lado = min(rect.width, rect.height) * glyph.opticalScale
        let transformacao = CGAffineTransform(scaleX: lado, y: lado)
            .concatenating(CGAffineTransform(
                translationX: rect.midX - lado / 2,
                y: rect.midY - lado / 2))
        return glyph.unitPath.applying(transformacao)
    }
}

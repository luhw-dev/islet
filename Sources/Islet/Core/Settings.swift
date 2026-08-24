import Foundation
import Combine

/// Material do halo de desfoque ao redor da ilha aberta.
///
/// Nenhuma opção é "só desfoque": o macOS não deixa um app ler os pixels de
/// outras janelas, então o desfoque sempre vem acompanhado de um material —
/// e todo material ou clareia ou escurece o que está atrás.
enum HaloStyle: String, CaseIterable {
    /// Vidro do Tahoe: refrata, mas clareia um pouco.
    case vidro
    /// Material clássico: borra mais, e escurece.
    case escuro
    case nenhum

    var title: String {
        switch self {
        case .vidro: return "Halo de vidro (clareia)"
        case .escuro: return "Halo escuro (escurece)"
        case .nenhum: return "Sem halo"
        }
    }
}

/// Como a ilha reage ao mouse.
enum ActivationMode: String, CaseIterable {
    /// Passar o mouse por cima expande (padrão).
    case hover
    /// O mouse não faz nada. Clicar no centro expande; clicar na lateral com
    /// música toca/pausa direto, sem precisar abrir.
    case click

    var title: String {
        switch self {
        case .hover: return "Passar o mouse expande"
        case .click: return "Clicar expande (clique na música pausa)"
        }
    }
}

/// Preferências persistidas em UserDefaults.
final class Settings: ObservableObject {
    private enum Key {
        static let simulateOnExternal = "simulateOnExternal"
        static let showOnNotchedScreen = "showOnNotchedScreen"
        static let simulatedWidth = "simulatedWidth"
        static let announceTrackChanges = "announceTrackChanges"
        static let activation = "activation"
        static let showSystemHUD = "showSystemHUD"
        static let interceptMediaKeys = "interceptMediaKeys"
        static let hapticFeedback = "hapticFeedback"
        static let haloStyle = "haloStyle"
    }

    /// Desenha uma ilha falsa em telas sem notch (monitores externos).
    @Published var simulateOnExternal: Bool {
        didSet { defaults.set(simulateOnExternal, forKey: Key.simulateOnExternal) }
    }

    /// Usa o notch físico do MacBook quando existir.
    @Published var showOnNotchedScreen: Bool {
        didSet { defaults.set(showOnNotchedScreen, forKey: Key.showOnNotchedScreen) }
    }

    /// Largura do "notch" desenhado em telas sem notch.
    @Published var simulatedWidth: Double {
        didSet { defaults.set(simulatedWidth, forKey: Key.simulatedWidth) }
    }

    /// Abre a ilha sozinha por alguns segundos quando a música muda.
    @Published var announceTrackChanges: Bool {
        didSet { defaults.set(announceTrackChanges, forKey: Key.announceTrackChanges) }
    }

    @Published var activation: ActivationMode {
        didSet { defaults.set(activation.rawValue, forKey: Key.activation) }
    }

    /// Mostra volume e brilho na ilha quando você mexe neles.
    @Published var showSystemHUD: Bool {
        didSet { defaults.set(showSystemHUD, forKey: Key.showSystemHUD) }
    }

    /// Assume as teclas de volume e brilho. É o que faz o HUD nativo sumir —
    /// e exige permissão de Acessibilidade.
    @Published var interceptMediaKeys: Bool {
        didSet { defaults.set(interceptMediaKeys, forKey: Key.interceptMediaKeys) }
    }

    /// Retorno tátil no trackpad.
    @Published var hapticFeedback: Bool {
        didSet {
            defaults.set(hapticFeedback, forKey: Key.hapticFeedback)
            Haptics.enabled = hapticFeedback
        }
    }

    @Published var haloStyle: HaloStyle {
        didSet { defaults.set(haloStyle.rawValue, forKey: Key.haloStyle) }
    }

    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Key.simulateOnExternal: true,
            Key.showOnNotchedScreen: true,
            Key.simulatedWidth: 190.0,
            Key.announceTrackChanges: true,
            Key.activation: ActivationMode.hover.rawValue,
            Key.showSystemHUD: true,
            Key.interceptMediaKeys: true,
            Key.hapticFeedback: true,
            Key.haloStyle: HaloStyle.vidro.rawValue
        ])
        simulateOnExternal = defaults.bool(forKey: Key.simulateOnExternal)
        showOnNotchedScreen = defaults.bool(forKey: Key.showOnNotchedScreen)
        simulatedWidth = defaults.double(forKey: Key.simulatedWidth)
        announceTrackChanges = defaults.bool(forKey: Key.announceTrackChanges)
        activation = ActivationMode(rawValue: defaults.string(forKey: Key.activation) ?? "") ?? .hover
        showSystemHUD = defaults.bool(forKey: Key.showSystemHUD)
        interceptMediaKeys = defaults.bool(forKey: Key.interceptMediaKeys)
        hapticFeedback = defaults.bool(forKey: Key.hapticFeedback)
        haloStyle = HaloStyle(rawValue: defaults.string(forKey: Key.haloStyle) ?? "") ?? .vidro
        Haptics.enabled = hapticFeedback
    }
}

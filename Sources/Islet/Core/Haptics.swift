import AppKit

/// Retorno tátil no trackpad.
///
/// Só acontece em trackpads com Force Touch; em outros aparelhos a chamada é
/// silenciosamente ignorada pelo sistema, então não precisa de verificação.
enum Haptics {
    /// Espelha o ajuste; assim os pontos de chamada não precisam conhecê-lo.
    static var enabled = true

    /// Ação comum: um botão, uma cópia, um arquivo solto.
    static func tap() {
        perform(.generic)
    }

    /// Algo se encaixou: troca de página, fim de um arraste na barra.
    static func snap() {
        perform(.alignment)
    }

    /// Um degrau numa escala: volume, brilho.
    static func step() {
        perform(.levelChange)
    }

    private static func perform(_ padrao: NSHapticFeedbackManager.FeedbackPattern) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(padrao, performanceTime: .now)
    }
}

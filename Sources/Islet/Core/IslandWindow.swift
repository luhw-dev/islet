import AppKit
import SwiftUI

/// View que só captura o mouse dentro do desenho da ilha; o resto da janela
/// é transparente de verdade e deixa o clique passar para o app de baixo.
final class PassthroughView: NSView {
    var hitRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

/// Painel sem borda, sempre no topo, presente em todos os Spaces.
final class IslandWindow: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Acima da barra de menus, inclusive sobre apps em tela cheia.
        level = NSWindow.Level(rawValue: Int(NSWindow.Level.mainMenu.rawValue) + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        let container = PassthroughView(frame: CGRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        contentView = container
    }

    /// Nunca. Não há campo de texto na ilha, e um painel sem borda que vira
    /// janela chave passa a receber o teclado — quem estiver digitando perde as
    /// teclas para uma janela que não faz nada com elas. Botões, gestos e
    /// arrastar-e-soltar funcionam sem ser chave.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var passthroughView: PassthroughView? { contentView as? PassthroughView }
}

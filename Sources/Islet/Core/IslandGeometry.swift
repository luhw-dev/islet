import AppKit

/// Medidas fixas do desenho da ilha.
enum Metrics {
    /// Raio dos cantos côncavos que encostam na borda de cima da tela.
    static let wingRadius: CGFloat = 10
    /// Raio dos cantos convexos de baixo.
    ///
    /// O macOS 26 Tahoe adotou 26 pt nas janelas com toolbar, no desenho
    /// concêntrico; a ilha aberta acompanha para parecer parte do sistema.
    /// Recolhida ela segue o canto do notch físico, que é bem menor.
    static let bottomRadiusExpanded: CGFloat = 34
    static let bottomRadiusCollapsed: CGFloat = 14
    static let bottomRadiusHUD: CGFloat = 16

    static let expandedWidth: CGFloat = 360
    /// Cabeçalho + progresso + controles + respiro de baixo.
    /// Mais estreita e mais alta que o padrão de dashboard: a proporção do
    /// Alcove é quase 2:1, não 2,3:1.
    static let expandedRowSpacing: CGFloat = 10
    static let expandedBottomPadding: CGFloat = 10
    static let expandedHeaderHeight: CGFloat = 54
    static let expandedProgressHeight: CGFloat = 16
    static let expandedControlsHeight: CGFloat = 42
    static let expandedContentHeight: CGFloat = expandedHeaderHeight + expandedRowSpacing
        + expandedProgressHeight + expandedRowSpacing + expandedControlsHeight
        + expandedBottomPadding
    /// A prateleira só entra na altura quando tem algo nela.
    static let shelfHeight: CGFloat = 48
    /// A janela é sempre deste tamanho; o que muda é o recorte desenhado dentro dela.
    static let windowSize = CGSize(width: 620, height: 300)

    /// Altura da ilha simulada em telas sem notch.
    static let simulatedHeight: CGFloat = 32
    /// Quanto a ilha cresce de cada lado quando tem indicador no modo recolhido.
    static let compactSideWidth: CGFloat = 46

    /// Crescimento sutil quando o mouse encosta na ilha recolhida: é o que
    /// avisa que dali dá para clicar, antes de qualquer coisa abrir.
    static let hoverBumpWidth: CGFloat = 12
    static let hoverBumpHeight: CGFloat = 4

    /// "Peek": o mini-expandido que aparece no hover, com o nome da faixa.
    /// Serve de convite — mostra que ali dá para clicar.
    static let peekWidth: CGFloat = 330
    static let peekTextHeight: CGFloat = 34
    /// A linha de cima do peek cresce além do notch para caber uma capa maior.
    static let peekTopExtra: CGFloat = 12
    static let compactArtworkSize: CGFloat = 26
    static let peekArtworkSize: CGFloat = 38
    static let bottomRadiusPeek: CGFloat = 22

    /// HUD de volume/brilho: ícone de um lado do notch, barra do outro.
    ///
    /// Os dois lados têm a MESMA largura de propósito — é isso que mantém o vão
    /// do desenho em cima do notch físico, que é centralizado na tela. A barra
    /// encolhe para caber nesse orçamento em vez de invadir o vão.
    static let hudSideWidth: CGFloat = 100
    static let hudBarWidth: CGFloat = 48
    static let hudValueWidth: CGFloat = 24
    static let hudEdgePadding: CGFloat = 14
    static let hudMinHeight: CGFloat = 32
}

/// Geometria de uma tela: notch real quando existe, ilha desenhada quando não.
struct IslandGeometry {
    let displayID: CGDirectDisplayID
    let hasNotch: Bool
    /// Tamanho do "miolo" no estado recolhido (o notch físico, ou a pílula simulada).
    let notchSize: CGSize
    /// Frame da janela em coordenadas globais do AppKit.
    let windowFrame: CGRect

    init?(screen: NSScreen, settings: Settings) {
        guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        displayID = CGDirectDisplayID(number.uint32Value)

        let physicalNotch = Debug.forceSimulated ? nil : IslandGeometry.physicalNotchSize(of: screen)
        if let physicalNotch {
            guard settings.showOnNotchedScreen else { return nil }
            hasNotch = true
            notchSize = physicalNotch
        } else {
            guard settings.simulateOnExternal else { return nil }
            hasNotch = false
            notchSize = CGSize(width: settings.simulatedWidth, height: Metrics.simulatedHeight)
        }

        let size = Metrics.windowSize
        windowFrame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Mede o notch de verdade pelas áreas auxiliares da barra de menus.
    static func physicalNotchSize(of screen: NSScreen) -> CGSize? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        let height = screen.safeAreaInsets.top
        guard width > 1, height > 1 else { return nil }
        return CGSize(width: width, height: height)
    }

}

import SwiftUI

/// O contorno da ilha: cantos de baixo com a curvatura contínua da Apple
/// (squircle) e, em cima, dois cantos côncavos que "derretem" na borda da tela.
///
/// Os cantos de baixo não são desenhados à mão: pegamos o path de um
/// `RoundedRectangle(style: .continuous)`, que já é a curva exata do sistema, e
/// unimos com as asas. Aproximar superelipse na unha erra justamente no que
/// diferencia a squircle de um arco comum.
struct NotchShape: Shape {
    var wingRadius: CGFloat = Metrics.wingRadius
    var bottomRadius: CGFloat = Metrics.bottomRadiusCollapsed

    /// Anima junto com a mudança de tamanho da ilha.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(wingRadius, bottomRadius) }
        set {
            wingRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let bodyMinX = rect.minX + wingRadius
        let bodyMaxX = rect.maxX - wingRadius
        guard bodyMaxX > bodyMinX else { return Path(rect) }

        // A curva contínua consome ~1,53 raio ao longo de cada aresta. Se o
        // corpo começasse na borda da tela, essa entrada apareceria como uma
        // barriga para dentro nas laterais; então ele sobe para fora da tela.
        let sobra = bottomRadius * 1.7
        let corpo = CGRect(
            x: bodyMinX,
            y: rect.minY - sobra,
            width: bodyMaxX - bodyMinX,
            height: rect.height + sobra
        )
        let base = RoundedRectangle(cornerRadius: bottomRadius, style: .continuous).path(in: corpo)

        guard wingRadius > 0 else { return base }

        var asas = Path()
        asas.addPath(wing(topX: rect.minX, bodyX: bodyMinX, topY: rect.minY))
        asas.addPath(wing(topX: rect.maxX, bodyX: bodyMaxX, topY: rect.minY))

        return Path(base.cgPath.union(asas.cgPath))
    }

    /// Pedaço côncavo entre a borda da tela e a lateral do corpo.
    private func wing(topX: CGFloat, bodyX: CGFloat, topY: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: topX, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: bodyX, y: topY + wingRadius),
            control: CGPoint(x: bodyX, y: topY)
        )
        path.addLine(to: CGPoint(x: bodyX, y: topY))
        path.closeSubpath()
        return path
    }
}

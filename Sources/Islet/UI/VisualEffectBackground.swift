import AppKit
import SwiftUI

/// Desfoque do que está atrás da janela — inclusive de outras janelas.
///
/// Este é o único caminho que funciona. `backgroundFilters` da CALayer parece
/// resolver e compila, mas só filtra o conteúdo da própria janela: o macOS não
/// deixa um app amostrar pixels de outras janelas, e o WindowServer é quem
/// compõe tudo. Só `NSVisualEffectView` com `.behindWindow` tem essa permissão.
///
/// O preço é a tinta: todo material pinta uma cor junto do desfoque, e não
/// existe material neutro. `.fullScreenUI` é dos mais discretos.
struct BackdropBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    /// Abaixo de 1 a tinta clareia — junto com um pouco do desfoque.
    var strength: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        // .active mantém o desfoque com o app em segundo plano, que é o estado
        // normal de um app de barra de menus.
        view.state = .active
        view.isEmphasized = false
        view.appearance = NSAppearance(named: .darkAqua)
        aplicar(em: view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        aplicar(em: view)
    }

    private func aplicar(em view: NSVisualEffectView) {
        view.material = material
        view.alphaValue = strength
    }
}

import AppKit
import SwiftUI
import Combine

/// Amarra uma tela, sua janela e o estado da ilha.
@MainActor
final class IslandController {
    let model: IslandModel
    private let window: IslandWindow
    private var cancellables = Set<AnyCancellable>()

    init(geometry: IslandGeometry, app: AppModel) {
        model = IslandModel(geometry: geometry, app: app)
        window = IslandWindow(frame: geometry.windowFrame)

        let root = IslandView(model: model)
            .environmentObject(app.battery)
            .environmentObject(app.settings)
            .environmentObject(app.nowPlaying)
            .environmentObject(app.audioOutput)
            .environmentObject(app.clipboard)
            .environmentObject(app.shelf)
            .environmentObject(app.usage)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: geometry.windowFrame.size)
        hosting.autoresizingMask = [.width, .height]
        window.passthroughView?.addSubview(hosting)

        updateHitRect()
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()

        model.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                self.updateHitRect()
                app.nowPlaying.setExpanded(mode == .expanded, key: ObjectIdentifier(self.model))
            }
            .store(in: &cancellables)

        app.battery.$isCharging
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] charging in
                guard let self else { return }
                self.updateHitRect()
                if charging { self.model.flash(.expanded) }
            }
            .store(in: &cancellables)

        app.nowPlaying.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                // As orelhas aparecem/somem: a área clicável muda junto.
                self.updateHitRect()

                let novaFaixa = snapshot?.trackID
                defer { self.lastTrackID = novaFaixa }
                guard app.settings.announceTrackChanges,
                      let novaFaixa,
                      let anterior = self.lastTrackID,
                      anterior != novaFaixa,
                      snapshot?.isPlaying == true else { return }
                // Troca de faixa avisa no peek, não abrindo a ilha inteira.
                self.model.flash(.peek, for: 2.5)
            }
            .store(in: &cancellables)

        app.hud.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else { return }
                // Brilho é da tela onde mudou; volume vale para todas.
                if let display = event.displayID, display != self.model.geometry.displayID { return }
                self.model.showHUD(event)
            }
            .store(in: &cancellables)
    }

    private var lastTrackID: String?
    /// Trackpad reporta deslocamento em pontos (dezenas por gesto); rodinha de
    /// mouse reporta poucos incrementos por clique. Um limiar só serviria mal
    /// para os dois.
    private static let limiarPreciso: CGFloat = 30
    private static let limiarPorCliques: CGFloat = 3
    private var scrollAcumulado: CGFloat = 0
    private var scrollAcumuladoX: CGFloat = 0
    private var trocouNestaSequencia = false
    private var ultimoScroll: TimeInterval = 0

    /// A área sensível ao mouse acompanha o tamanho atual do desenho.
    private func updateHitRect() {
        window.passthroughView?.hitRect = model.hitRect
    }

    /// Retângulo da ilha em coordenadas globais, usado para detectar o hover.
    var triggerRect: CGRect {
        let origin = window.frame.origin
        // Uma folga pequena facilita acertar a ilha sem precisar de mira.
        return model.hitRect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -4, dy: -4)
    }

    func updateHover(mouseLocation: CGPoint) {
        // Recalcular aqui é trivial e evita ter que assinar cada coisa que
        // muda o tamanho (mídia, bateria, prateleira, modo).
        updateHitRect()
        let rect = triggerRect
        let dentro = rect.contains(mouseLocation)

        // Devolver nil no hitTest só faz o evento ser DESCARTADO — ele não cai
        // para o app de baixo. Para o clique atravessar de verdade a janela
        // precisa ignorar o mouse enquanto o cursor não está sobre a ilha.
        if window.ignoresMouseEvents != !dentro {
            window.ignoresMouseEvents = !dentro
            Debug.log("cursor \(dentro ? "entrou" : "saiu") | mouse=\(mouseLocation) trigger=\(rect) ignoresMouse=\(window.ignoresMouseEvents)")
        }

        if dentro {
            model.setHovering(true, zone: model.zone(forGlobalPoint: mouseLocation, islandRect: rect))
        } else {
            model.setHovering(false)
        }
    }

    /// Um swipe vertical troca de página — uma vez por sequência de scroll,
    /// senão a inércia do trackpad passaria três páginas de uma vez.
    /// Devolve true quando o evento virou troca de página (e não deve seguir
    /// para o conteúdo).
    @discardableResult
    func handleScroll(_ evento: NSEvent) -> Bool {
        guard model.mode == .expanded else { return false }

        // Trackpad manda .began; rodinha de mouse não manda fase nenhuma, então
        // uma pausa entre eventos também conta como sequência nova.
        if evento.phase == .began || evento.timestamp - ultimoScroll > 0.25 {
            scrollAcumulado = 0
            scrollAcumuladoX = 0
            trocouNestaSequencia = false
        }
        ultimoScroll = evento.timestamp
        if evento.phase == .ended || evento.momentumPhase == .ended {
            scrollAcumulado = 0
            scrollAcumuladoX = 0
            return false
        }

        scrollAcumuladoX += evento.scrollingDeltaX
        scrollAcumulado += evento.scrollingDeltaY
        let limiar = evento.hasPreciseScrollingDeltas ? Self.limiarPreciso : Self.limiarPorCliques
        guard !trocouNestaSequencia else { return false }

        // Horizontal sempre pagina. Vertical só quando a página não tem lista
        // para rolar — senão o mesmo gesto teria dois donos.
        if abs(scrollAcumuladoX) >= limiar, abs(scrollAcumuladoX) > abs(scrollAcumulado) {
            trocouNestaSequencia = true
            model.mudarPagina(avancando: scrollAcumuladoX < 0)
            return true
        }
        if !model.page.temListaRolavel, abs(scrollAcumulado) >= limiar {
            trocouNestaSequencia = true
            model.mudarPagina(avancando: scrollAcumulado < 0)
            return true
        }
        return false
    }

    func close() {
        model.app.nowPlaying.setExpanded(false, key: ObjectIdentifier(model))
        cancellables.removeAll()
        window.orderOut(nil)
        window.close()
    }
}

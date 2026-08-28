import AppKit
import Combine

/// Cria uma ilha por tela e mantém isso em dia quando o arranjo de monitores muda.
@MainActor
final class DisplayManager {
    private let app: AppModel
    private var controllers: [IslandController] = []
    private var mouseTimer: Timer?
    private var scrollMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(app: AppModel) {
        self.app = app

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        app.settings.$simulateOnExternal
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        app.settings.$showOnNotchedScreen
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        rebuild()
        startMouseTracking()
        startScrollMonitor()
    }

    func rebuild() {
        controllers.forEach { $0.close() }
        controllers = NSScreen.screens.compactMap { screen in
            guard let geometry = IslandGeometry(screen: screen, settings: app.settings) else { return nil }
            return IslandController(geometry: geometry, app: app)
        }
        if !Debug.testShelf.isEmpty {
            controllers.forEach { $0.model.addToShelf(Debug.testShelf) }
        }
        if Debug.openOnLaunch {
            let pagina: IslandPage? = switch Debug.openPage {
            case "shelf": .shelf
            case "clipboard": .clipboard
            case "usage": .usage
            case "media": .media
            default: nil
            }
            controllers.forEach { controlador in
                if let pagina { controlador.model.page = pagina }
                controlador.model.flash(.expanded, for: 120)
            }
        }
    }

    /// O swipe precisa ser visto antes das views: a `NSHostingView` do SwiftUI
    /// consome o scroll e ele nunca chegaria à janela.
    private func startScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] evento in
            MainActor.assumeIsolated {
                guard let self else { return evento }
                // Roteia por posição do cursor, e não por `evento.window`: em
                // painel sem borda a janela do evento nem sempre vem preenchida.
                let cursor = NSEvent.mouseLocation
                let dono = self.controllers.first { $0.triggerRect.contains(cursor) }
                Debug.log("scroll dy=\(evento.scrollingDeltaY) preciso=\(evento.hasPreciseScrollingDeltas)")
                guard let dono else { return evento }
                return dono.handleScroll(evento) ? nil : evento
            }
        }
    }

    /// Em vez de tracking areas (que exigem a janela grande e roubariam cliques),
    /// olhamos a posição do cursor. Também funciona durante um drag de arquivo.
    private func startMouseTracking() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let location = NSEvent.mouseLocation
                for controller in self.controllers {
                    controller.updateHover(mouseLocation: location)
                }
                // Brilho e área de transferência pegam carona aqui, em vez de
                // abrir um timer cada um.
                self.app.hud.tick()
                self.app.clipboard.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }
}

import AppKit
import Combine

enum IslandMode: Equatable {
    case collapsed
    /// Mini-expandido do hover: só a faixa tocando, como convite ao clique.
    case peek
    case expanded
    /// Mostrando volume ou brilho no lugar do HUD do sistema.
    case hud
}

/// O que a ilha expandida está mostrando. Troca por swipe.
enum IslandPage: Int, CaseIterable {
    case media
    case shelf
    case clipboard
    case usage

    /// Páginas com lista própria ficam com o eixo vertical: ali o swipe para
    /// baixo rola o conteúdo, e a troca de página fica só no horizontal.
    var temListaRolavel: Bool { self == .clipboard }
}

/// Onde o cursor está sobre a ilha recolhida.
enum HoverZone: Equatable {
    case none
    /// Capa do álbum.
    case leading
    /// Em cima do notch.
    case center
    /// Waveform — vira botão de pausa no hover.
    case trailing
}

/// O que aparece nas laterais quando a ilha está recolhida.
enum CompactContent: Equatable {
    case none
    case media
    case charging
}

/// Estado de uma ilha (uma instância por tela).
@MainActor
final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .collapsed {
        didSet {
            guard mode != oldValue else { return }
            Debug.log("modo \(oldValue) -> \(mode) (zona=\(hoverZone))")
        }
    }
    @Published var isDropTargeted = false
    /// Segura a ilha aberta por um tempo mesmo sem o mouse em cima (ex.: avisou que ligou na tomada).
    @Published private(set) var isPinnedOpen = false
    @Published private(set) var hud: HUDEvent?
    @Published private(set) var hoverZone: HoverZone = .none
    @Published private(set) var isHovering = false
    @Published var page: IslandPage = .media
    @Published private(set) var isMenuOpen = false

    let geometry: IslandGeometry
    let app: AppModel

    private var pinTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?
    private var hudTask: Task<Void, Never>?
    private var expansaoTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()


    init(geometry: IslandGeometry, app: AppModel) {
        self.geometry = geometry
        self.app = app

        // Desligar a página de uso com ela na tela deixaria a ilha numa página
        // que não existe mais.
        app.settings.$showUsage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] ativo in
                guard let self, !ativo, self.page == .usage else { return }
                self.page = .media
            }
            .store(in: &cancellables)
    }

    /// Páginas que entram no swipe agora. A de uso some quando desligada nos
    /// ajustes — e some junto das bolinhas, para não virar um passo vazio.
    var visiblePages: [IslandPage] {
        IslandPage.allCases.filter { $0 != .usage || app.settings.showUsage }
    }

    var hasNotch: Bool { geometry.hasNotch }

    /// No estado recolhido mostramos as "orelhas" só quando tem algo a dizer.
    /// Música ganha de bateria: é o que muda com mais frequência.
    var compactContent: CompactContent {
        if app.nowPlaying.snapshot != nil { return .media }
        if app.battery.isCharging { return .charging }
        return .none
    }

    var showsCompactSides: Bool { compactContent != .none }

    var hasMedia: Bool { app.nowPlaying.snapshot != nil }

    /// A prateleira some quando está vazia: sem ela a ilha fica do tamanho da
    /// referência, e ela reaparece assim que chega arquivo.
    var showsShelf: Bool { !app.shelf.items.isEmpty || isDropTargeted }

    /// O quanto a ilha recolhida cresce com o mouse em cima.
    var hoverBump: (width: CGFloat, height: CGFloat) {
        isHovering ? (Metrics.hoverBumpWidth, Metrics.hoverBumpHeight) : (0, 0)
    }

    /// Altura da linha de cima do peek. Passa do notch de propósito: é o que
    /// permite a capa ser maior do que a faixa do recolhido comporta.
    var peekTopHeight: CGFloat {
        geometry.notchSize.height + Metrics.hoverBumpHeight + Metrics.peekTopExtra
    }

    /// Em telas com notch, a faixa de cima fica escondida atrás dele.
    var contentTopInset: CGFloat {
        hasNotch ? geometry.notchSize.height + 2 : 8
    }

    /// Tamanho do miolo desenhado. A "asa" côncava fica fora dele.
    var bodySize: CGSize {
        switch mode {
        case .collapsed:
            let extra = showsCompactSides ? Metrics.compactSideWidth * 2 : 0
            return CGSize(
                width: geometry.notchSize.width + extra + hoverBump.width,
                height: geometry.notchSize.height + hoverBump.height)
        case .hud:
            // Com notch, o corpo é o notch mais a área da direita. Sem notch, a
            // pílula só precisa caber ícone e barra.
            let lados = Metrics.hudSideWidth * 2
            let largura = hasNotch ? geometry.notchSize.width + lados
                                   : max(geometry.notchSize.width, lados)
            return CGSize(
                width: largura,
                height: max(geometry.notchSize.height, Metrics.hudMinHeight))
        case .peek:
            // Mesma largura e mesma altura de topo do recolhido sob o mouse: o
            // peek só acrescenta a linha de baixo, sem deslocar capa e wave.
            return CGSize(
                width: geometry.notchSize.width + Metrics.compactSideWidth * 2 + Metrics.hoverBumpWidth,
                height: peekTopHeight + Metrics.peekTextHeight)
        case .expanded:
            // Altura fixa entre páginas: trocar de conteúdo não pode fazer a
            // ilha pular de tamanho debaixo do cursor.
            return CGSize(
                width: Metrics.expandedWidth,
                height: contentTopInset + Metrics.expandedContentHeight)
        }
    }

    var bottomRadius: CGFloat {
        switch mode {
        case .expanded: return Metrics.bottomRadiusExpanded
        case .peek: return Metrics.bottomRadiusPeek
        case .hud: return Metrics.bottomRadiusHUD
        case .collapsed: return Metrics.bottomRadiusCollapsed
        }
    }

    /// Área sensível dentro da janela (coordenadas AppKit, origem embaixo).
    var hitRect: CGRect {
        let body = bodySize
        let largura = body.width + Metrics.wingRadius * 2
        return CGRect(
            x: (Metrics.windowSize.width - largura) / 2,
            y: Metrics.windowSize.height - body.height,
            width: largura,
            height: body.height)
    }

    /// Em qual zona da ilha está esse ponto (coordenadas globais do AppKit).
    ///
    /// O mapa é o mesmo no recolhido e no peek: capa à esquerda, notch no meio,
    /// waveform à direita. Assim o gesto não muda de sentido quando a ilha
    /// cresce debaixo do cursor.
    func zone(forGlobalPoint ponto: CGPoint, islandRect: CGRect) -> HoverZone {
        guard hasMedia else { return .center }

        switch mode {
        case .collapsed:
            guard showsCompactSides else { return .center }
            let corpo = bodySize
            let inicio = islandRect.midX - corpo.width / 2
            if ponto.x < inicio + Metrics.compactSideWidth { return .leading }
            if ponto.x > inicio + corpo.width - Metrics.compactSideWidth { return .trailing }
            return .center

        case .peek:
            // A faixa de texto de baixo não abre nada: dá para ler o nome da
            // música sem a ilha saltar para o tamanho cheio.
            if ponto.y < islandRect.maxY - peekTopHeight { return .leading }
            let meiaLargura = geometry.notchSize.width / 2
            if ponto.x < islandRect.midX - meiaLargura { return .leading }
            if ponto.x > islandRect.midX + meiaLargura { return .trailing }
            return .center

        default:
            return .center
        }
    }

    var activation: ActivationMode { app.settings.activation }

    func setHovering(_ hovering: Bool, zone: HoverZone = .center) {
        let estavaSobre = isHovering
        isHovering = hovering
        let novaZona = hovering ? zone : .none
        if hoverZone != novaZona { hoverZone = novaZona }
        guard !isPinnedOpen, !isMenuOpen else { return }

        guard hovering else {
            cancelarExpansao()
            // Só age na saída de verdade. Isto aqui roda 30 vezes por segundo
            // enquanto o cursor está fora: reagendar a cada quadro reiniciava
            // o temporizador e ele nunca chegava ao fim.
            guard estavaSobre else { return }
            switch mode {
            case .peek:
                mode = .collapsed
            case .expanded:
                // Sair da ilha recolhe nos dois modos. No clique fica uma folga
                // curta, só para tolerar o cursor raspando a borda de saída.
                if activation == .hover {
                    mode = .collapsed
                } else {
                    scheduleAutoCollapse(after: 0.6)
                }
            default:
                break
            }
            return
        }

        dismissHUD()
        cancelAutoCollapse()

        // Cada parte da ilha recolhida tem seu próprio gesto.
        switch novaZona {
        case .leading:
            // Capa: mini-expandido com o nome da faixa, e nada além disso.
            if mode == .collapsed, hasMedia { mode = .peek }
        case .trailing:
            // Waveform: vira botão de pausa; a ilha não cresce.
            if mode == .peek { mode = .collapsed }
        case .center:
            // Um respiro antes de abrir: dá tempo do crescimento ser percebido,
            // em vez da ilha saltar para o tamanho cheio no primeiro pixel.
            // Vale a partir do peek também: quem entrou pela capa precisa
            // conseguir abrir tudo só andando para o meio.
            if activation == .hover, mode == .collapsed || mode == .peek {
                agendarExpansao(after: 0.18)
            }
        case .none:
            break
        }
    }

    private func agendarExpansao(after atraso: Double) {
        guard expansaoTask == nil else { return }
        expansaoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(atraso * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.expansaoTask = nil
                guard !Task.isCancelled, self.isHovering, self.hoverZone == .center,
                      self.mode == .collapsed || self.mode == .peek else { return }
                self.mode = .expanded
            }
        }
    }

    private func cancelarExpansao() {
        expansaoTask?.cancel()
        expansaoTask = nil
    }

    func setMenuOpen(_ open: Bool) {
        isMenuOpen = open
        if open { cancelAutoCollapse() }
    }

    /// Swipe vertical troca a página exibida.
    func mudarPagina(avancando: Bool) {
        let paginas = visiblePages
        guard let atual = paginas.firstIndex(of: page) else { return }
        let proximo = avancando
            ? (atual + 1) % paginas.count
            : (atual - 1 + paginas.count) % paginas.count
        page = paginas[proximo]
        Haptics.snap()
        Debug.log("pagina -> \(page)")
    }

    func toggleExpanded() {
        pinTask?.cancel()
        isPinnedOpen = false
        cancelAutoCollapse()
        mode = mode == .expanded ? .collapsed : .expanded
        if mode == .expanded, !isHovering { scheduleAutoCollapse() }
    }

    /// Clique na faixa do meio (em cima do notch): abre e fecha.
    func handleCenterTap() {
        toggleExpanded()
    }

    /// Clique no waveform: pausa direto, sem abrir nada.
    func handleTrailingTap() {
        if mode == .collapsed || mode == .peek, hasMedia {
            Haptics.tap()
            app.nowPlaying.togglePlayPause()
        } else {
            toggleExpanded()
        }
    }

    /// Clique na capa: segue o modo de ativação.
    func handleLeadingTap() {
        if activation == .click || mode == .peek {
            toggleExpanded()
        }
    }

    /// Mostra volume/brilho por um instante, no lugar do HUD do macOS.
    func showHUD(_ event: HUDEvent) {
        guard app.settings.showSystemHUD else { return }
        // Se a pessoa já está mexendo na ilha, não sequestramos — mas se o HUD
        // já está na tela, precisa continuar aceitando: sem isso a barra
        // congela no primeiro valor enquanto a tecla segue apertada.
        guard mode == .collapsed || mode == .hud else { return }

        hud = event
        mode = .hud
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismissHUD() }
        }
    }

    /// Sair do HUD sempre volta para o recolhido. Deixar o modo em `.hud` sem
    /// conteúdo desenhava uma ilha grande e vazia — era o que acontecia quando
    /// o mouse encostava com o HUD de volume na tela.
    private func dismissHUD() {
        hudTask?.cancel()
        hudTask = nil
        guard hud != nil else { return }
        hud = nil
        if mode == .hud { mode = .collapsed }
    }

    private func scheduleAutoCollapse(after seconds: Double = 5) {
        cancelAutoCollapse()
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isHovering, !self.isPinnedOpen else { return }
                self.mode = .collapsed
            }
        }
    }

    private func cancelAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }

    /// Mostra a ilha sozinha por alguns segundos, no tamanho pedido.
    ///
    /// Só interrompe ilha parada: se ela já está aberta — trocando de faixa
    /// pelos próprios botões, por exemplo — encolher para o aviso tiraria da
    /// pessoa justamente o que ela está usando.
    func flash(_ destino: IslandMode, for seconds: Double = 3) {
        guard mode == .collapsed else { return }
        pinTask?.cancel()
        isPinnedOpen = true
        mode = destino
        pinTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.isPinnedOpen = false
                // Se o mouse está em cima no modo hover, continua aberta.
                if self.activation == .hover, self.isHovering { return }
                self.mode = .collapsed
            }
        }
    }

    /// Arquivo pairando sobre a ilha: abre direto na prateleira e trava aberta
    /// enquanto durar o arraste — sem isso a ilha se fecharia embaixo do
    /// cursor no meio do gesto.
    func beginDrop() {
        cancelAutoCollapse()
        page = .shelf
        isPinnedOpen = true
        if mode != .expanded {
            mode = .expanded
            Haptics.tap()
        }

        // Rede de segurança: se o aviso de "saiu" nunca chegar (o arraste é
        // cancelado de um jeito que o SwiftUI não reporta), a ilha ficaria
        // travada aberta para sempre.
        pinTask?.cancel()
        pinTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.endDrop() }
        }
    }

    /// Chamado quando o arquivo é solto ou o arraste sai de cima.
    func endDrop() {
        pinTask?.cancel()
        isPinnedOpen = false
        // Um respiro antes de fechar: dá tempo de ver o arquivo aterrissar.
        if !isHovering { scheduleAutoCollapse(after: 2) }
    }

    func addToShelf(_ urls: [URL]) {
        page = .shelf
        Haptics.tap()
        app.shelf.add(urls)
    }
}

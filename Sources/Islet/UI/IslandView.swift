import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var media: NowPlayingMonitor
    @EnvironmentObject private var clipboard: ClipboardMonitor
    @EnvironmentObject private var shelf: ShelfStore

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let corpo = model.bodySize
        let forma = NotchShape(bottomRadius: model.bottomRadius)
        return forma
            // Preto sólido: o desfoque é em volta, não através dela.
            .fill(Color.black)
            .frame(width: corpo.width + Metrics.wingRadius * 2, height: corpo.height)
            .overlay {
                content
                    .frame(width: corpo.width, height: corpo.height)
                    .clipped()
            }
            .overlay(alignment: .top) {
                // No modo clique, a faixa do notch continua sendo o botão de
                // abrir/fechar mesmo com a ilha aberta.
                if model.mode == .expanded, model.activation == .click {
                    Color.clear
                        .frame(width: model.geometry.notchSize.width, height: model.contentTopInset)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggleExpanded() }
                }
            }
            .shadow(
                color: .black.opacity(model.mode == .collapsed ? 0 : 0.55),
                radius: 16, y: 6)
            .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTargeted, perform: handleDrop)
            .onChange(of: model.isDropTargeted) { _, arrastando in
                if arrastando { model.beginDrop() } else { model.endDrop() }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.78), value: model.mode)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: corpo)
            .animation(.easeOut(duration: 0.16), value: model.hoverZone)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .collapsed, .peek:
            // Um ramo só de propósito: assim o SwiftUI mantém a capa e o
            // waveform vivos entre os dois estados e anima o tamanho, em vez
            // de dissolver um por cima do outro.
            compactoOuPeek.transition(.opacity)
        case .expanded:
            expanded.transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        case .hud:
            // Se por algum caminho o payload sumir, mostra o recolhido em vez
            // de uma ilha vazia.
            if model.hud != nil {
                hudView.transition(.opacity)
            } else {
                compactoOuPeek.transition(.opacity)
            }
        }
    }

    // MARK: - Recolhido

    @ViewBuilder
    private var compactoOuPeek: some View {
        let ehPeek = model.mode == .peek
        VStack(spacing: 0) {
            compactRow(artworkSize: ehPeek ? Metrics.peekArtworkSize : Metrics.compactArtworkSize)
                .frame(height: ehPeek ? model.peekTopHeight : model.bodySize.height)

            if ehPeek, let snapshot = media.snapshot {
                peekTextRow(snapshot)
                    .frame(height: Metrics.peekTextHeight)
                    // A linha nasce de baixo da faixa de cima, como se estivesse
                    // escondida ali o tempo todo.
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .clipped()
    }

    private func peekTextRow(_ snapshot: MediaSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(snapshot.title)
                .foregroundStyle(.white)
                + Text("  ·  ")
                .foregroundStyle(.white.opacity(0.4))
                + Text(snapshot.artist)
                .foregroundStyle(.white.opacity(0.6))
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleExpanded() }
    }

    /// Capa | vão do notch | waveform. É a mesma linha no recolhido e no peek,
    /// então nada se desloca quando a linha de texto entra embaixo.
    private func compactRow(artworkSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            leadingIndicator(artworkSize: artworkSize)
                .frame(width: model.showsCompactSides ? Metrics.compactSideWidth : 0)
                .contentShape(Rectangle())
                .onTapGesture { model.handleLeadingTap() }

            // Espaço do notch físico (ou do miolo da pílula) fica sempre vazio.
            Color.clear
                .frame(width: model.geometry.notchSize.width)
                .contentShape(Rectangle())
                .onTapGesture { model.handleCenterTap() }

            trailingIndicator
                .frame(width: model.showsCompactSides ? Metrics.compactSideWidth : 0)
                .contentShape(Rectangle())
                .onTapGesture { model.handleTrailingTap() }
        }
    }

    @ViewBuilder
    private func leadingIndicator(artworkSize: CGFloat) -> some View {
        switch model.compactContent {
        case .media:
            ArtworkView(image: media.artwork, size: artworkSize)
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        switch model.compactContent {
        case .media:
            // Parar o mouse em cima troca o waveform pelo botão de pausa.
            if model.hoverZone == .trailing {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .foregroundStyle(.white)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            } else {
                Waveform(
                    isPlaying: media.isPlaying,
                    tint: media.palette.primary,
                    height: 14
                )
                .frame(
                    width: WaveformLayerView.tamanho(altura: 14).width,
                    height: 14
                )
                .transition(.opacity)
            }
        case .charging:
            Text("\(battery.percentage)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(battery.percentage)))
                .animation(.snappy, value: battery.percentage)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Expandido

    private var expanded: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.contentTopInset)

            paginaAtual
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(model.page)
                // O swipe é vertical, então a página entra pelo mesmo eixo.
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, Metrics.expandedBottomPadding)
        .clipped()
        .overlay(alignment: .bottom) { pontosDePagina }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.page)
    }

    @ViewBuilder
    private var paginaAtual: some View {
        switch model.page {
        case .media: paginaMidia
        case .shelf: paginaPrateleira
        case .clipboard: paginaTransferencia
        }
    }

    /// Bolinhas discretas: sem elas o swipe seria um recurso invisível.
    private var pontosDePagina: some View {
        HStack(spacing: 4) {
            ForEach(IslandPage.allCases, id: \.rawValue) { pagina in
                Capsule()
                    .fill(Color.white.opacity(pagina == model.page ? 0.65 : 0.2))
                    .frame(width: pagina == model.page ? 10 : 4, height: 4)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { model.page = pagina }
            }
        }
        .padding(.bottom, 3)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.page)
    }

    // MARK: - Página: mídia

    @ViewBuilder
    private var paginaMidia: some View {
        VStack(spacing: Metrics.expandedRowSpacing) {
            if let snapshot = media.snapshot {
                NowPlayingHeader(snapshot: snapshot).frame(height: Metrics.expandedHeaderHeight)
                NowPlayingProgress(snapshot: snapshot).frame(height: Metrics.expandedProgressHeight)
                NowPlayingControls(model: model, snapshot: snapshot)
                    .frame(height: Metrics.expandedControlsHeight)
            } else if media.automationDenied {
                estadoVazio(
                    "Libere Ajustes › Privacidade › Automação",
                    icone: "exclamationmark.triangle",
                    cor: .orange)
            } else {
                // Sem música a página fica com um bloco só; centralizar evita o
                // vazio no topo com tudo empurrado para o rodapé.
                HStack(alignment: .center) {
                    BatteryBadge()
                    Spacer(minLength: 8)
                    ClockBlock()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Página: prateleira

    private var paginaPrateleira: some View {
        ShelfView(model: model)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if !shelf.items.isEmpty {
                    BotaoDeLixeira { shelf.clear() }
                        .padding(6)
                }
            }
    }

    // MARK: - Página: área de transferência

    private var paginaTransferencia: some View {
        VStack(alignment: .leading, spacing: 6) {
            cabecalhoDePagina(
                clipboard.items.isEmpty ? "Copiados" : "Copiados · \(clipboard.items.count)",
                icone: "doc.on.clipboard"
            ) {
                guard !clipboard.items.isEmpty else { return nil }
                return ("Limpar", { clipboard.clear() })
            }

            if clipboard.items.isEmpty {
                estadoVazio("Nada copiado ainda", icone: "doc.on.clipboard")
            } else {
                // A lista rola na vertical porque a paginação saiu desse eixo:
                // aqui o swipe para os lados é que troca de página.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(clipboard.items) { item in
                            ClipboardRow(
                                item: item,
                                onCopy: { clipboard.copy(item) },
                                onRemove: { clipboard.remove(item) })
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Peças comuns

    private func cabecalhoDePagina(
        _ titulo: String,
        icone: String,
        acao: () -> (String, () -> Void)?
    ) -> some View {
        HStack {
            Label(titulo, systemImage: icone)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            if let (nome, executar) = acao() {
                Button(nome, action: executar)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private func estadoVazio(_ texto: String, icone: String, cor: Color = .white) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icone)
                .font(.system(size: 18, weight: .light))
            Text(texto)
                .font(.system(size: 11))
        }
        .foregroundStyle(cor.opacity(0.35))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - HUD de volume e brilho

    @ViewBuilder
    private var hudView: some View {
        if let event = model.hud {
            HStack(spacing: 0) {
                // Ícone e rótulo encostados na borda esquerda.
                HStack(spacing: 6) {
                    Image(systemName: Self.symbol(for: event))
                        .font(.system(size: 13, weight: .semibold))
                    Text(Self.label(for: event))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.leading, Metrics.hudEdgePadding)
                .frame(width: Metrics.hudSideWidth, alignment: .leading)

                // O vão do notch físico fica vazio.
                if model.hasNotch {
                    Color.clear.frame(width: model.geometry.notchSize.width)
                }

                // Barra e, só no som, o valor numérico — como no original: o
                // brilho não mostra número, e a barra ocupa o espaço dele.
                HStack(spacing: 8) {
                    HUDBar(
                        value: event.muted ? 0 : event.value,
                        tint: Self.tint(for: event)
                    )
                    .frame(width: Self.barWidth(for: event))

                    if event.kind == .volume {
                        let porcento = Int((event.muted ? 0 : event.value) * 100)
                        Text("\(porcento)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            // Odômetro: só o dígito que muda rola.
                            .contentTransition(.numericText(value: Double(porcento)))
                            .animation(.snappy, value: porcento)
                            .frame(width: Metrics.hudValueWidth, alignment: .trailing)
                    }
                }
                .padding(.trailing, Metrics.hudEdgePadding)
                .frame(width: Metrics.hudSideWidth, alignment: .trailing)
            }
        }
    }

    private static func barWidth(for event: HUDEvent) -> CGFloat {
        switch event.kind {
        case .volume: return Metrics.hudBarWidth
        case .brightness: return Metrics.hudBarWidth + Metrics.hudValueWidth + 8
        }
    }

    private static func label(for event: HUDEvent) -> String {
        switch event.kind {
        case .volume: return event.muted ? "Muted" : "Sound"
        case .brightness: return "Display"
        }
    }

    private static func tint(for event: HUDEvent) -> Color {
        switch event.kind {
        case .volume: return .green
        case .brightness: return .white
        }
    }

    private static func symbol(for event: HUDEvent) -> String {
        switch event.kind {
        case .brightness:
            return "sun.max.fill"
        case .volume:
            if event.muted { return "speaker.slash.fill" }
            switch event.value {
            case ..<0.01: return "speaker.fill"
            case ..<0.34: return "speaker.wave.1.fill"
            case ..<0.67: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        }
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var aceitou = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            aceitou = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.addToShelf([url]) }
            }
        }
        return aceitou
    }
}

/// Barra do HUD de volume e brilho.
private struct HUDBar: View {
    let value: Double
    var tint: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.18), value: value)
    }
}

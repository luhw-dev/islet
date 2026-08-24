import SwiftUI
import CoreAudio

/// Capa com fallback para quando ainda não baixou (ou o player não expõe).
///
/// O raio sai do tamanho em vez de vir de fora: é o que garante a mesma forma
/// de squircle na miniatura de 26 pt e na capa de 54, sem cada ponto de chamada
/// ter que acertar o número.
struct ArtworkView: View {
    let image: NSImage?
    var size: CGFloat

    /// Proporção dos ícones da Apple; abaixo disso a curva contínua não se
    /// distingue de um retângulo arredondado comum.
    private var radius: CGFloat { size * 0.235 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

/// Waveform: várias barrinhas em movimento, tingidas pela capa do álbum.
///
/// Em SwiftUI puro isso custava ~5% de CPU o tempo todo, porque cada quadro da
/// animação disparava um ciclo de layout do AppKit na janela inteira. Aqui a
/// animação vive em CALayer, então roda no render server e o main thread não
/// faz nada por quadro.
struct Waveform: NSViewRepresentable {
    var isPlaying: Bool
    var tint: NSColor
    var height: CGFloat = 16

    func makeNSView(context: Context) -> WaveformLayerView {
        WaveformLayerView(altura: height)
    }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        view.apply(isPlaying: isPlaying && !Debug.staticEqualizer, tint: tint)
    }
}

final class WaveformLayerView: NSView {
    /// Envelope das barras: mais altas no meio, como um waveform de verdade.
    private static let escalas: [CGFloat] = [0.40, 0.75, 1.00, 0.62, 0.85]
    private static let larguraBarra: CGFloat = 1.8
    private static let espaco: CGFloat = 2.2

    static func tamanho(altura: CGFloat) -> CGSize {
        let n = CGFloat(escalas.count)
        return CGSize(width: n * larguraBarra + (n - 1) * espaco, height: altura)
    }

    private let altura: CGFloat
    private var barras: [CALayer] = []
    /// nil até a primeira aplicação: uma view recém-criada precisa assumir
    /// a forma certa mesmo que o estado já seja o "padrão".
    private var animando: Bool?

    init(altura: CGFloat) {
        self.altura = altura
        super.init(frame: CGRect(origin: .zero, size: Self.tamanho(altura: altura)))
        wantsLayer = true
        layer?.masksToBounds = false

        barras = Self.escalas.map { _ in
            let barra = CALayer()
            barra.cornerRadius = Self.larguraBarra / 2
            barra.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(barra)
            return barra
        }
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    override var intrinsicContentSize: NSSize { Self.tamanho(altura: altura) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (indice, barra) in barras.enumerated() {
            let x = CGFloat(indice) * (Self.larguraBarra + Self.espaco) + Self.larguraBarra / 2
            barra.bounds = CGRect(x: 0, y: 0, width: Self.larguraBarra, height: altura)
            barra.position = CGPoint(x: x, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func apply(isPlaying: Bool, tint: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for barra in barras {
            barra.backgroundColor = tint.cgColor
        }
        CATransaction.commit()

        guard isPlaying != animando else { return }
        animando = isPlaying

        for (indice, barra) in barras.enumerated() {
            barra.removeAnimation(forKey: "wave")
            guard isPlaying else {
                // Parado, cada barra encolhe até virar um ponto: como o raio já
                // é metade da largura, o quadrado resultante sai redondo.
                barra.transform = CATransform3DMakeScale(1, Self.larguraBarra / altura, 1)
                continue
            }
            barra.transform = CATransform3DIdentity

            let animacao = CABasicAnimation(keyPath: "transform.scale.y")
            animacao.fromValue = Self.escalas[indice]
            animacao.toValue = Self.escalas[(indice + 2) % Self.escalas.count]
            // Durações levemente diferentes para as barras saírem de sincronia
            // e o conjunto não pulsar como um bloco só.
            animacao.duration = 0.42 + Double(indice % 4) * 0.09
            animacao.autoreverses = true
            animacao.repeatCount = .infinity
            animacao.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animacao.beginTime = CACurrentMediaTime() + Double(indice) * 0.07
            barra.add(animacao, forKey: "wave")
        }
    }
}

/// Cabeçalho: capa, título/artista e o waveform tingido pela capa.
struct NowPlayingHeader: View {
    @EnvironmentObject private var media: NowPlayingMonitor
    let snapshot: MediaSnapshot

    private static let waveHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(image: media.artwork, size: 54)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .id(snapshot.trackID)
                .transition(.scale(scale: 0.82).combined(with: .opacity))

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(snapshot.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(snapshot.trackID)
            // Faixa nova entra deslizando de baixo, como na Dynamic Island.
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity))

            Waveform(
                isPlaying: snapshot.isPlaying,
                tint: media.palette.primary,
                height: Self.waveHeight
            )
            .frame(
                width: WaveformLayerView.tamanho(altura: Self.waveHeight).width,
                height: Self.waveHeight
            )
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: snapshot.trackID)
    }
}

/// Barra de progresso arrastável: decorrido à esquerda, o que falta à direita.
struct NowPlayingProgress: View {
    @EnvironmentObject private var media: NowPlayingMonitor
    let snapshot: MediaSnapshot

    @State private var hovering = false
    /// Enquanto arrasta, a barra segue o dedo e ignora o player.
    @State private var scrub: Double?

    private var fracao: Double {
        if let scrub { return scrub }
        guard snapshot.duration > 0 else { return 0 }
        return min(1, max(0, media.position / snapshot.duration))
    }

    private var segundosMostrados: Double { fracao * snapshot.duration }
    private var ativo: Bool { hovering || scrub != nil }

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.tempo(segundosMostrados))
                .contentTransition(.numericText(countsDown: false))
                .animation(.snappy, value: Int(segundosMostrados))
                .frame(width: 38, alignment: .leading)

            barra

            Text("-" + Self.tempo(max(0, snapshot.duration - segundosMostrados)))
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: Int(snapshot.duration - segundosMostrados))
                .frame(width: 42, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(ativo ? 0.75 : 0.5))
        .monospacedDigit()
        .animation(.easeOut(duration: 0.2), value: ativo)
    }

    private var barra: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(media.palette.secondaryColor)
                    .frame(width: geo.size.width * fracao)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .frame(width: ativo ? 11 : 0, height: ativo ? 11 : 0)
                    .offset(x: geo.size.width * fracao - (ativo ? 5.5 : 0))
            }
            .frame(height: ativo ? 8 : 5)
            .frame(maxHeight: .infinity)
            // Área de pegada maior que o desenho: barra fina é difícil de acertar.
            .contentShape(Rectangle())
            .onHover { estaSobre in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    hovering = estaSobre
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { valor in
                        scrub = min(1, max(0, valor.location.x / geo.size.width))
                    }
                    .onEnded { valor in
                        let destino = min(1, max(0, valor.location.x / geo.size.width))
                        media.seek(toFraction: destino)
                        Haptics.snap()
                        scrub = nil
                    }
            )
            .animation(scrub == nil ? .linear(duration: 0.45) : nil, value: fracao)
        }
        .frame(height: 18)
    }

    static func tempo(_ segundos: Double) -> String {
        guard segundos.isFinite, segundos >= 0 else { return "--:--" }
        let total = Int(segundos.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Linha de controles: aleatório, faixas, play/pause e saída de áudio.
struct NowPlayingControls: View {
    @EnvironmentObject private var media: NowPlayingMonitor
    @ObservedObject var model: IslandModel
    let snapshot: MediaSnapshot

    var body: some View {
        HStack(spacing: 0) {
            MediaButton(
                symbol: "shuffle",
                size: 16,
                opacity: snapshot.shuffling ? 1 : 0.42,
                tint: snapshot.shuffling ? media.palette.primaryColor : .white
            ) { media.toggleShuffle() }

            Spacer()
            MediaButton(symbol: "backward.fill", size: 21) { media.previous() }
            Spacer()
            MediaButton(
                symbol: snapshot.isPlaying ? "pause.fill" : "play.fill",
                size: 28,
                weight: .semibold
            ) { media.togglePlayPause() }
            Spacer()
            MediaButton(symbol: "forward.fill", size: 21) { media.next() }
            Spacer()

            OutputDeviceButton(model: model)
        }
    }
}

/// Ícone reflete a saída atual; o clique lista as outras.
///
/// Usa NSMenu direto em vez de `Menu` do SwiftUI: dentro de um painel sem borda
/// e não-ativante, o menu do SwiftUI simplesmente não desenha.
struct OutputDeviceButton: View {
    @EnvironmentObject private var output: AudioOutputManager
    @ObservedObject var model: IslandModel

    var body: some View {
        MediaButton(
            symbol: output.current?.symbol ?? "hifispeaker",
            size: 18,
            opacity: 0.5
        ) { mostrarMenu() }
        .onAppear { output.refresh() }
    }

    private func mostrarMenu() {
        output.refresh()
        let menu = NSMenu()
        menu.items = output.devices.map { device in
            let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            item.state = device.id == output.current?.id ? .on : .off
            item.representedObject = device.id
            item.target = MenuTarget.shared
            item.action = #selector(MenuTarget.selecionar(_:))
            return item
        }
        MenuTarget.shared.onSelect = { id in
            guard let device = output.devices.first(where: { $0.id == id }) else { return }
            output.select(device)
        }

        // Enquanto o menu está aberto a ilha não pode se recolher embaixo dele.
        model.setMenuOpen(true)
        var ponto = NSEvent.mouseLocation
        ponto.y -= 6
        menu.popUp(positioning: nil, at: ponto, in: nil)
        model.setMenuOpen(false)
    }
}

/// NSMenuItem precisa de um alvo Objective-C; SwiftUI View não serve.
private final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    var onSelect: ((AudioDeviceID) -> Void)?

    @objc func selecionar(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioDeviceID else { return }
        onSelect?(id)
    }
}

/// Botão redondo com realce no hover, recuo no clique e símbolo animado.
struct MediaButton: View {
    let symbol: String
    let size: CGFloat
    var weight: Font.Weight = .medium
    var opacity: Double = 0.85
    var tint: Color = .white
    let action: () -> Void

    @State private var hovering = false
    /// Cada clique incrementa e dispara o pulo do símbolo.
    @State private var pulsos = 0

    private var lado: CGFloat { size + 16 }
    /// Squircle, não círculo: é o realce que o resto do sistema usa, e casa
    /// com o canto contínuo da própria ilha.
    private var realce: RoundedRectangle {
        RoundedRectangle(cornerRadius: lado * 0.3, style: .continuous)
    }

    var body: some View {
        Button {
            pulsos += 1
            Haptics.tap()
            action()
        } label: {
            ZStack {
                realce
                    .fill(Color.white.opacity(hovering ? 0.13 : 0))
                    .scaleEffect(hovering ? 1 : 0.72)
                Image(systemName: symbol)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(tint.opacity(hovering ? 1 : opacity))
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .symbolEffect(.bounce, value: pulsos)
            }
            .frame(width: lado, height: lado)
            .contentShape(realce)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { estaSobre in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                hovering = estaSobre
            }
        }
    }
}

/// Recuo elástico no clique — o feedback tátil que falta em botão de SwiftUI.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

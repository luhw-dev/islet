import AppKit
import Combine

/// Aplica volume e brilho quando assumimos as teclas de mídia.
@MainActor
final class MediaKeyController {
    /// Mesmos passos do sistema: 1/16, ou 1/64 com Shift+Option.
    private static let passo: Float = 1.0 / 16.0
    private static let passoFino: Float = 1.0 / 64.0

    private let tap = MediaKeyTap()
    private let hud: SystemHUDMonitor
    private let settings: Settings
    private var cancellables = Set<AnyCancellable>()
    private var esperandoPermissao: Timer?
    /// Teclas cujo "pressionar" nós engolimos — o "soltar" tem que ir junto.
    private var engolidas = Set<MediaKey>()

    var isRunning: Bool { tap.isRunning }
    var needsPermission: Bool { settings.interceptMediaKeys && !MediaKeyTap.hasPermission }

    init(hud: SystemHUDMonitor, settings: Settings) {
        self.hud = hud
        self.settings = settings

        tap.handler = { [weak self] toque in
            self?.tratar(toque) ?? false
        }

        settings.$interceptMediaKeys
            .receive(on: RunLoop.main)
            .sink { [weak self] ligado in self?.setEnabled(ligado) }
            .store(in: &cancellables)
    }

    func setEnabled(_ ligado: Bool) {
        Debug.log("permissões: Acessibilidade=\(MediaKeyTap.hasAccessibility) "
                  + "MonitoramentoDeEntrada=\(MediaKeyTap.hasInputMonitoring)")
        guard ligado else {
            esperandoPermissao?.invalidate()
            esperandoPermissao = nil
            tap.stop()
            return
        }

        if tap.start() {
            Debug.log("teclas de mídia assumidas")
            return
        }
        Debug.log("sem permissão de Acessibilidade; aguardando autorização")

        // Sem permissão: pede e fica tentando, para funcionar assim que a
        // pessoa autorizar, sem precisar reabrir o app.
        MediaKeyTap.requestPermission()
        guard esperandoPermissao == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.settings.interceptMediaKeys else {
                    timer.invalidate()
                    return
                }
                if self.tap.start() {
                    Debug.log("permissão concedida; teclas de mídia assumidas")
                    timer.invalidate()
                    self.esperandoPermissao = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        esperandoPermissao = timer
    }

    /// Abre o painel de Ajustes do que está faltando.
    ///
    /// Deliberadamente não abrimos alerta modal aqui. Um app acessório que
    /// chama `NSApp.activate(ignoringOtherApps:)` e `runModal()` rouba o foco
    /// de quem está digitando e trava a thread principal — o custo de avisar
    /// não pode ser sequestrar a máquina. Quem avisa é o menu da barra.
    func abrirAjustesDePermissao() {
        let painel = MediaKeyTap.hasAccessibility
            ? "Privacy_ListenEvent"
            : "Privacy_Accessibility"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(painel)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Tratamento

    private func tratar(_ toque: MediaKeyPress) -> Bool {
        Debug.log("tecla \(toque.key) down=\(toque.isDown)")
        guard toque.isDown else {
            // Solta junto o que engolimos, senão o sistema vê meio evento.
            return engolidas.remove(toque.key) != nil
        }

        let aplicou: Bool
        switch toque.key {
        case .soundUp:
            aplicou = ajustarVolume(passos: 1, fino: toque.fineStep)
        case .soundDown:
            aplicou = ajustarVolume(passos: -1, fino: toque.fineStep)
        case .mute:
            aplicou = alternarMudo()
        case .brightnessUp:
            aplicou = ajustarBrilho(passos: 1, fino: toque.fineStep)
        case .brightnessDown:
            aplicou = ajustarBrilho(passos: -1, fino: toque.fineStep)
        }

        // Se não conseguimos aplicar, devolvemos a tecla ao sistema: melhor ver
        // o HUD nativo do que ficar sem controle de volume.
        if aplicou {
            engolidas.insert(toque.key)
            // Um toque por degrau: segurando a tecla, vira uma escadinha.
            Haptics.step()
        }
        return aplicou
    }

    private func ajustarVolume(passos: Float, fino: Bool) -> Bool {
        let dispositivo = AudioVolume.defaultDevice()
        guard let atual = AudioVolume.current(dispositivo) else { return false }

        let incremento = fino ? Self.passoFino : Self.passo
        let alvo = ((atual / incremento).rounded() + passos) * incremento

        // Subir o volume tira do mudo, como o sistema faz.
        if passos > 0, AudioVolume.isMuted(dispositivo) {
            AudioVolume.setMuted(false, on: dispositivo)
        }
        return AudioVolume.set(alvo, on: dispositivo)
    }

    private func alternarMudo() -> Bool {
        let dispositivo = AudioVolume.defaultDevice()
        guard AudioVolume.current(dispositivo) != nil else { return false }
        return AudioVolume.setMuted(!AudioVolume.isMuted(dispositivo), on: dispositivo)
    }

    private func ajustarBrilho(passos: Float, fino: Bool) -> Bool {
        guard let tela = DisplayBrightness.controllableDisplay(),
              let atual = DisplayBrightness.current(tela) else { return false }

        let incremento = fino ? Self.passoFino : Self.passo
        let alvo = min(1, max(0, ((atual / incremento).rounded() + passos) * incremento))
        guard DisplayBrightness.set(alvo, on: tela) else { return false }

        // O brilho não tem notificação: avisamos o HUD na hora, sem esperar a
        // amostragem, senão a barra chega atrasada na própria tecla.
        hud.emitBrightness(value: Double(alvo), displayID: tela)
        return true
    }
}

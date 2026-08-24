import AppKit
import Combine
import CoreAudio

enum HUDKind: Equatable {
    case volume
    case brightness
}

struct HUDEvent: Equatable {
    var kind: HUDKind
    /// 0...1
    var value: Double
    var muted: Bool
    /// Brilho é por tela; volume vale para todas.
    var displayID: CGDirectDisplayID?
}

/// Volume e brilho do sistema, para a ilha substituir o HUD do macOS.
///
/// Volume vem por listener do CoreAudio (só dispara quando muda de verdade).
/// Brilho não tem notificação pública, então é amostrado — mas de carona no
/// timer que já acompanha o mouse, sem timer novo.
@MainActor
final class SystemHUDMonitor {
    let events = PassthroughSubject<HUDEvent, Never>()

    private var deviceID = AudioDeviceID(0)
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var muteBlock: AudioObjectPropertyListenerBlock?
    private var deviceBlock: AudioObjectPropertyListenerBlock?

    private var brightnessGetter: BrightnessGetter?
    private var lastBrightness: [CGDirectDisplayID: Double] = [:]
    private var brightnessTick = 0

    /// Um passo de tecla mexe ~6%. Só reagimos a saltos assim, para o brilho
    /// automático (que passeia devagar) não ficar piscando a ilha à toa.
    private static let brightnessThreshold = 0.02
    /// Ler brilho é um XPC síncrono para o CoreBrightness — caro demais para
    /// fazer o tempo todo. Em repouso amostramos devagar; quando o brilho
    /// começa a mudar, aceleramos por alguns segundos para acompanhar o
    /// pressionar da tecla, e voltamos ao ritmo lento depois.
    private static let ticksEmRepouso = 6   // 5 Hz
    private static let ticksAcelerado = 2   // 15 Hz
    private static let ticksDeAceleracao = 60  // ~2 s
    private var aceleracaoRestante = 0

    init() {
        setupBrightness()
        attachToDefaultDevice()
        observeDefaultDeviceChanges()
    }

    // MARK: - Volume

    private func attachToDefaultDevice() {
        detachDeviceListeners()
        deviceID = Self.defaultOutputDevice()
        guard deviceID != 0 else { return }

        var volumeAddr = Self.volumeAddress
        if AudioObjectHasProperty(deviceID, &volumeAddr) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.emitVolume() }
            }
            volumeBlock = block
            AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddr, DispatchQueue.main, block)
        }

        var muteAddr = Self.muteAddress
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.emitVolume() }
            }
            muteBlock = block
            AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main, block)
        }
    }

    /// Trocar de saída (fone, monitor, AirPods) muda o device: reatacha.
    private func observeDefaultDeviceChanges() {
        var addr = Self.defaultDeviceAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }

    private func detachDeviceListeners() {
        guard deviceID != 0 else { return }
        if let volumeBlock {
            var addr = Self.volumeAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, volumeBlock)
        }
        if let muteBlock {
            var addr = Self.muteAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, DispatchQueue.main, muteBlock)
        }
        volumeBlock = nil
        muteBlock = nil
    }

    private func emitVolume() {
        guard let volume = Self.currentVolume(deviceID) else { return }
        events.send(HUDEvent(
            kind: .volume,
            value: Double(volume),
            muted: Self.isMuted(deviceID),
            displayID: nil
        ))
    }

    // MARK: - Brilho

    private typealias BrightnessGetter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private func setupBrightness() {
        // Não existe API pública para ler brilho; DisplayServices é privado mas
        // continua acessível sem entitlement (diferente do MediaRemote).
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return }
        brightnessGetter = unsafeBitCast(symbol, to: BrightnessGetter.self)
        sampleBrightness(emit: false)
    }

    /// Chamado pelo timer do DisplayManager (30 Hz).
    func tick() {
        guard !Debug.noBrightness else { return }
        brightnessTick += 1
        let intervalo = aceleracaoRestante > 0 ? Self.ticksAcelerado : Self.ticksEmRepouso
        if aceleracaoRestante > 0 { aceleracaoRestante -= 1 }
        guard brightnessTick % intervalo == 0 else { return }
        sampleBrightness(emit: true)
    }

    private func sampleBrightness(emit: Bool) {
        guard let getter = brightnessGetter else { return }
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            var valor: Float = 0
            // Telas externas costumam não responder: aí simplesmente ignoramos.
            guard getter(id, &valor) == 0 else { continue }
            let novo = Double(valor)
            defer { lastBrightness[id] = novo }
            guard emit, let anterior = lastBrightness[id] else { continue }
            guard abs(novo - anterior) >= Self.brightnessThreshold else { continue }
            aceleracaoRestante = Self.ticksDeAceleracao
            events.send(HUDEvent(kind: .brightness, value: novo, muted: false, displayID: id))
        }
    }

    /// Emite o brilho na hora — usado quando somos nós que mexemos nele, para
    /// a barra não esperar a próxima amostragem.
    func emitBrightness(value: Double, displayID: CGDirectDisplayID) {
        lastBrightness[displayID] = value
        aceleracaoRestante = Self.ticksDeAceleracao
        events.send(HUDEvent(kind: .brightness, value: value, muted: false, displayID: displayID))
    }

    // MARK: - CoreAudio cru

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static func defaultOutputDevice() -> AudioDeviceID {
        var addr = defaultDeviceAddress
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func currentVolume(_ device: AudioDeviceID) -> Float? {
        guard device != 0 else { return nil }
        var addr = volumeAddress
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var valor = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &valor) == noErr else { return nil }
        return valor
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool {
        var addr = muteAddress
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var valor = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &valor) == noErr else { return false }
        return valor != 0
    }
}

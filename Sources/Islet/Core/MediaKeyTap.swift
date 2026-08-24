import AppKit
import ApplicationServices
import IOKit.hid

enum MediaKey: Int32, CaseIterable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

struct MediaKeyPress {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    /// Shift+Option: passo fino, como no próprio macOS.
    let fineStep: Bool
}

/// Intercepta as teclas de volume e brilho antes do sistema.
///
/// É o único jeito conhecido de não ver o HUD nativo no macOS 26: o popover é
/// desenhado pelo Control Center e não há defaults nem API para desligá-lo, mas
/// se a tecla nunca chega ao sistema, ele não tem o que desenhar. Em troca, o
/// app passa a ser responsável por de fato mudar volume e brilho — por isso só
/// engolimos a tecla quando conseguimos aplicar a mudança.
///
/// Exige permissão de Acessibilidade. Como a permissão é atrelada à assinatura
/// do binário, recompilar o app costuma exigir concedê-la de novo.
@MainActor
final class MediaKeyTap {
    /// Devolva true para engolir a tecla.
    var handler: ((MediaKeyPress) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Acessibilidade é o que basta para criar um tap que consome eventos.
    /// Monitoramento de Entrada só entra em cena se, com ela concedida, o
    /// sistema ainda recusar — não faz sentido pedir mais do que o necessário.
    static var hasPermission: Bool { hasAccessibility }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static var hasInputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Abre os pedidos do sistema (uma vez cada; depois o macOS só mostra os Ajustes).
    static func requestPermission() {
        guard hasAccessibility else {
            let chave = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([chave: true] as CFDictionary)
            return
        }
        // Só escala para a segunda permissão se a primeira já valia e mesmo
        // assim o tap não subiu.
        if !hasInputMonitoring {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    /// Quais permissões ainda faltam, para a interface poder dizer.
    static var missingPermissions: [String] {
        if !hasAccessibility { return ["Acessibilidade"] }
        if !hasInputMonitoring { return ["Monitoramento de Entrada"] }
        return []
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        // 14 = NSEventTypeSystemDefined, onde vivem as teclas de mídia.
        let mascara = CGEventMask(1 << 14)
        let contexto = Unmanaged.passUnretained(self).toOpaque()

        guard let novoTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mascara,
            callback: { _, tipo, evento, contexto in
                guard let contexto else { return Unmanaged.passUnretained(evento) }
                let tap = Unmanaged<MediaKeyTap>.fromOpaque(contexto).takeUnretainedValue()
                return MainActor.assumeIsolated { tap.processar(tipo: tipo, evento: evento) }
            },
            userInfo: contexto
        ) else {
            return false
        }

        let novaFonte = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, novoTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), novaFonte, .commonModes)
        CGEvent.tapEnable(tap: novoTap, enable: true)

        tap = novoTap
        source = novaFonte
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func processar(tipo: CGEventType, evento: CGEvent) -> Unmanaged<CGEvent>? {
        // O sistema desliga o tap se o callback demorar; religar é por nossa conta.
        if tipo == .tapDisabledByTimeout || tipo == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(evento)
        }

        guard tipo.rawValue == 14,
              let nsEvento = NSEvent(cgEvent: evento),
              nsEvento.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(evento)
        }

        let dados = nsEvento.data1
        let codigo = Int32((dados & 0xFFFF_0000) >> 16)
        guard let tecla = MediaKey(rawValue: codigo) else {
            return Unmanaged.passUnretained(evento)
        }

        let flags = dados & 0x0000_FFFF
        let pressionada = ((flags & 0xFF00) >> 8) == 0x0A
        let repetindo = (flags & 0x1) == 1
        let passoFino = nsEvento.modifierFlags.isSuperset(of: [.shift, .option])

        let toque = MediaKeyPress(
            key: tecla, isDown: pressionada, isRepeat: repetindo, fineStep: passoFino)

        return handler?(toque) == true ? nil : Unmanaged.passUnretained(evento)
    }
}

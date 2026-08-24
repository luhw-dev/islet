import AppKit
import CoreAudio

/// Volume da saída padrão, via CoreAudio.
enum AudioVolume {
    static func defaultDevice() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// nil quando a saída não expõe volume (certos HDMI e interfaces externas).
    static func current(_ device: AudioDeviceID = defaultDevice()) -> Float? {
        guard device != 0 else { return nil }
        var addr = volumeAddress
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var valor = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &valor) == noErr else { return nil }
        return valor
    }

    @discardableResult
    static func set(_ valor: Float, on device: AudioDeviceID = defaultDevice()) -> Bool {
        guard device != 0 else { return false }
        var addr = volumeAddress
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var ajustavel = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &addr, &ajustavel) == noErr,
              ajustavel.boolValue else { return false }
        var novo = Float32(min(1, max(0, valor)))
        let status = AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &novo)
        return status == noErr
    }

    static func isMuted(_ device: AudioDeviceID = defaultDevice()) -> Bool {
        var addr = muteAddress
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var valor = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &valor) == noErr else { return false }
        return valor != 0
    }

    @discardableResult
    static func setMuted(_ mudo: Bool, on device: AudioDeviceID = defaultDevice()) -> Bool {
        var addr = muteAddress
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var valor = UInt32(mudo ? 1 : 0)
        return AudioObjectSetPropertyData(
            device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valor) == noErr
    }
}

/// Brilho, via DisplayServices (privado, mas sem entitlement).
enum DisplayBrightness {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32
    /// Avisa o sistema para ele persistir o novo valor e atualizar a UI dele.
    private typealias Notifier = @convention(c) (CGDirectDisplayID, Double) -> Void

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static let getter: Getter? = symbol("DisplayServicesGetBrightness")
    private static let setter: Setter? = symbol("DisplayServicesSetBrightness")
    private static let notifier: Notifier? = symbol("DisplayServicesBrightnessChanged")

    private static func symbol<T>(_ nome: String) -> T? {
        guard let handle, let ponteiro = dlsym(handle, nome) else { return nil }
        return unsafeBitCast(ponteiro, to: T.self)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let numero = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(numero.uint32Value)
    }

    /// nil quando a tela não responde — comum em monitores externos.
    static func current(_ display: CGDirectDisplayID) -> Float? {
        guard let getter else { return nil }
        var valor: Float = 0
        guard getter(display, &valor) == 0 else { return nil }
        return valor
    }

    @discardableResult
    static func set(_ valor: Float, on display: CGDirectDisplayID) -> Bool {
        guard let setter else { return false }
        let alvo = min(1, max(0, valor))
        guard setter(display, alvo) == 0 else { return false }
        notifier?(display, Double(alvo))
        return true
    }

    /// A primeira tela que responde — na prática, a interna.
    static func controllableDisplay() -> CGDirectDisplayID? {
        for screen in NSScreen.screens {
            guard let id = displayID(of: screen), current(id) != nil else { continue }
            return id
        }
        return nil
    }
}

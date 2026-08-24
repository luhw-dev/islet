import Foundation
import Combine
import IOKit.ps

/// Lê o estado da bateria via IOKit e avisa quando ele muda.
final class BatteryMonitor: ObservableObject {
    @Published private(set) var percentage: Int = 100
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var hasBattery: Bool = false
    /// Minutos até carregar de vez, quando o sistema sabe estimar.
    @Published private(set) var minutesToFull: Int?

    private var source: CFRunLoopSource?

    init() {
        refresh()
        startObserving()
    }

    deinit {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func startObserving() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { pointer in
            guard let pointer else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { monitor.refresh() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for item in list {
            guard let description = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let remaining = description[kIOPSTimeToFullChargeKey] as? Int ?? -1

            if percentage != percent { percentage = percent }
            if isCharging != charging { isCharging = charging }
            if isPluggedIn != plugged { isPluggedIn = plugged }
            minutesToFull = remaining > 0 ? remaining : nil
            if !hasBattery { hasBattery = true }
            return
        }

        // Mac de mesa: sem bateria interna.
        if hasBattery { hasBattery = false }
    }
}

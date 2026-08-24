import Foundation

/// Estado compartilhado por todas as ilhas (uma por tela).
@MainActor
final class AppModel {
    let settings = Settings()
    let battery = BatteryMonitor()
    let nowPlaying = NowPlayingMonitor()
    let hud = SystemHUDMonitor()
    let audioOutput = AudioOutputManager()
    let clipboard = ClipboardMonitor()
    lazy var mediaKeys = MediaKeyController(hud: hud, settings: settings)
}

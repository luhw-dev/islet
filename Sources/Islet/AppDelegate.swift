import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var app: AppModel!
    private var displays: DisplayManager!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            app = AppModel()
            displays = DisplayManager(app: app)
            // Toca o controller para ele se inscrever no ajuste e assumir as
            // teclas (é o que esconde o HUD nativo).
            _ = app.mediaKeys

            statusItem = StatusItemController(app: app) { [weak self] in
                self?.displays.rebuild()
            }

            if let fracao = Debug.testSeek {
                Task { @MainActor [app] in
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    Debug.log("teste: seek automático para \(fracao)")
                    app?.nowPlaying.seek(toFraction: fracao)
                }
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

import AppKit

/// De onde veio a música. Cada app tem seu dialeto de AppleScript.
enum MediaSource: String, CaseIterable {
    case spotify
    case music

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Música"
        }
    }

    /// Spotify devolve a duração em milissegundos; o Music, em segundos.
    var durationIsMilliseconds: Bool { self == .spotify }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

struct MediaSnapshot: Equatable {
    var source: MediaSource
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var artworkURL: String?
    var isPlaying: Bool
    var shuffling: Bool
}

/// Ponte com o AppleScript dos players. Todo acesso acontece numa fila serial,
/// porque NSAppleScript não gosta de ser chamado de várias threads.
final class MediaScripting {
    static let shared = MediaScripting()

    /// Vira true quando o macOS nega o controle por automação (erro -1743).
    private(set) var permissionDenied = false

    private let queue = DispatchQueue(label: "dev.aces.islet.applescript")
    private var compiled: [String: NSAppleScript] = [:]

    private init() {}

    // MARK: - Leitura

    func snapshot(completion: @escaping (MediaSnapshot?) -> Void) {
        let candidates = MediaSource.allCases.filter { $0.isRunning }
        queue.async { [weak self] in
            guard let self else { return DispatchQueue.main.async { completion(nil) } }
            var pausado: MediaSnapshot?
            for source in candidates {
                guard let snap = self.readSync(source) else { continue }
                if snap.isPlaying {
                    // Quem está tocando ganha na hora.
                    return DispatchQueue.main.async { completion(snap) }
                }
                if pausado == nil { pausado = snap }
            }
            DispatchQueue.main.async { completion(pausado) }
        }
    }

    private func readSync(_ source: MediaSource) -> MediaSnapshot? {
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application id "com.spotify.client"
                if player state is stopped then return {"stopped"}
                set t to current track
                return {(player state as text), (id of t) as text, (name of t) as text, ¬
                        (artist of t) as text, (album of t) as text, (duration of t), ¬
                        (player position), (artwork url of t) as text, (shuffling) as text}
            end tell
            """
        case .music:
            script = """
            tell application id "com.apple.Music"
                if player state is stopped then return {"stopped"}
                set t to current track
                return {(player state as text), (database ID of t) as text, (name of t) as text, ¬
                        (artist of t) as text, (album of t) as text, (duration of t), ¬
                        (player position), "", (shuffle enabled) as text}
            end tell
            """
        }

        guard let result = run(script, key: source.rawValue + ".read") else { return nil }
        guard result.numberOfItems >= 9 else { return nil }

        func item(_ index: Int) -> String {
            result.atIndex(index)?.stringValue ?? ""
        }

        /// Números vêm como número mesmo; o texto só entra como plano B, e aí
        /// pode chegar com vírgula decimal dependendo da região do sistema.
        func number(_ index: Int) -> Double {
            guard let descriptor = result.atIndex(index) else { return 0 }
            let valor = descriptor.doubleValue
            if valor != 0 { return valor }
            let texto = (descriptor.stringValue ?? "").replacingOccurrences(of: ",", with: ".")
            return Double(texto) ?? 0
        }

        let estado = item(1)
        guard estado != "stopped" else { return nil }

        let duracaoBruta = number(6)
        return MediaSnapshot(
            source: source,
            trackID: item(2),
            title: item(3),
            artist: item(4),
            album: item(5),
            duration: source.durationIsMilliseconds ? duracaoBruta / 1000 : duracaoBruta,
            position: number(7),
            artworkURL: item(8).isEmpty ? nil : item(8),
            isPlaying: estado == "playing",
            shuffling: item(9) == "true"
        )
    }

    /// O Music não expõe URL de capa, só os bytes da arte embutida.
    func localArtwork(for source: MediaSource, completion: @escaping (NSImage?) -> Void) {
        guard source == .music, source.isRunning else { return completion(nil) }
        queue.async { [weak self] in
            let script = """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """
            let data = self?.run(script, key: "music.artwork")?.data
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: - Controles

    func playPause(_ source: MediaSource) { command("playpause", on: source) }

    func setShuffle(_ ligado: Bool, on source: MediaSource) {
        let propriedade = source == .spotify ? "shuffling" : "shuffle enabled"
        command("set \(propriedade) to \(ligado)", on: source)
    }

    func setPosition(_ segundos: Double, on source: MediaSource) {
        // Ponto decimal explícito: o AppleScript não entende vírgula aqui.
        let valor = String(format: "%.2f", segundos)
        command("set player position to \(valor)", on: source, cache: false)
    }
    func next(_ source: MediaSource) { command("next track", on: source) }
    func previous(_ source: MediaSource) { command("previous track", on: source) }

    private func command(_ verb: String, on source: MediaSource, cache: Bool = true) {
        guard source.isRunning else { return }
        queue.async { [weak self] in
            _ = self?.run("tell application id \"\(source.bundleID)\" to \(verb)",
                          key: "\(source.rawValue).\(verb)", cache: cache)
        }
    }

    // MARK: - Execução

    /// `cache: false` para scripts que mudam a cada chamada (seek), senão o
    /// cache devolveria o script antigo com a posição velha.
    private func run(_ source: String, key: String, cache: Bool = true) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if cache, let existente = compiled[key] {
            script = existente
        } else {
            guard let novo = NSAppleScript(source: source) else { return nil }
            if cache { compiled[key] = novo }
            script = novo
        }

        var erro: NSDictionary?
        let result = script.executeAndReturnError(&erro)
        if let erro {
            let code = erro[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743: usuário negou automação. -600/-1728: app fechou no meio.
            if code == -1743 { permissionDenied = true }
            return nil
        }
        permissionDenied = false
        return result
    }
}

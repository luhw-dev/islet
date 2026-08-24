import AppKit
import Combine

/// O que está tocando agora.
///
/// O MediaRemote privado deixou de responder para apps sem entitlement (macOS
/// 15.4+), então a fonte de verdade aqui é o AppleScript de cada player, com as
/// notificações distribuídas servindo de gatilho para atualizar na hora.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var snapshot: MediaSnapshot?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette: ArtworkPalette = .fallback
    @Published private(set) var position: Double = 0
    @Published private(set) var automationDenied = false

    var isPlaying: Bool { snapshot?.isPlaying ?? false }
    var source: MediaSource? { snapshot?.source }

    private var anchorPosition: Double = 0
    private var anchorDate = Date()
    private var heartbeat: Timer?
    private var lastRefresh = Date.distantPast
    private var pendingRefresh: Task<Void, Never>?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkTrackID: String?
    /// Ilhas abertas neste momento. Sem nenhuma aberta, não vale a pena
    /// publicar progresso: ninguém está vendo a barra andar.
    private var expandedIslands = Set<ObjectIdentifier>()

    init() {
        observeNotifications()
        startTimers()
        refresh()
    }

    func setExpanded(_ expanded: Bool, key: ObjectIdentifier) {
        if expanded {
            expandedIslands.insert(key)
            interpolate()
            // Ao abrir, a posição pode estar velha: vale uma leitura na hora.
            refresh()
        } else {
            expandedIslands.remove(key)
        }
    }

    private var isVisible: Bool { !expandedIslands.isEmpty }

    // MARK: - Gatilhos

    private func observeNotifications() {
        let center = DistributedNotificationCenter.default()
        let nomes = [
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.Music.playerInfo",
            "com.apple.iTunes.playerInfo"
        ]
        for nome in nomes {
            center.addObserver(
                forName: Notification.Name(nome),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }
    }

    /// Cada consulta AppleScript custa dezenas de milissegundos (é um Apple
    /// Event de ida e volta até o player), então o intervalo acompanha o que
    /// está de fato visível. As notificações distribuídas cobrem play/pause e
    /// troca de faixa na hora; o polling só pega seek e controle externo.
    private var pollInterval: TimeInterval {
        if isVisible { return 1 }
        if snapshot?.isPlaying == true { return 10 }
        return 20
    }

    private func startTimers() {
        // Um timer só: menos despertares do processador do que dois.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.interpolate()
                if Date().timeIntervalSince(self.lastRefresh) >= self.pollInterval {
                    self.refresh()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    /// A notificação chega um pouco antes do player atualizar o próprio estado.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        lastRefresh = Date()
        MediaScripting.shared.snapshot { [weak self] snap in
            guard let self else { return }
            self.automationDenied = MediaScripting.shared.permissionDenied
            self.apply(snap)
        }
    }

    private func apply(_ snap: MediaSnapshot?) {
        guard let snap else {
            if snapshot != nil {
                snapshot = nil
                artwork = nil
                artworkTrackID = nil
                position = 0
            }
            return
        }

        let mudouFaixa = snapshot?.trackID != snap.trackID
        // Só publica se algo mudou de verdade: senão toda ilha redesenha a cada
        // leitura, inclusive as recolhidas.
        if snapshot != snap { snapshot = snap }
        anchorPosition = snap.position
        anchorDate = Date()
        if isVisible || mudouFaixa { position = snap.position }

        if mudouFaixa {
            loadArtwork(for: snap)
        }
    }

    private func interpolate() {
        guard isVisible, let snap = snapshot, snap.isPlaying else { return }
        let decorrido = Date().timeIntervalSince(anchorDate)
        position = min(snap.duration, anchorPosition + decorrido)
    }

    // MARK: - Capa

    private func loadArtwork(for snap: MediaSnapshot) {
        artworkTrackID = snap.trackID

        if let cache = artworkCache[snap.trackID] {
            artwork = cache
            palette = PaletteExtractor.palette(from: cache)
            return
        }
        artwork = nil
        palette = .fallback

        if let urlString = snap.artworkURL, let url = URL(string: urlString) {
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data) else { return }
                await MainActor.run {
                    guard let self, self.artworkTrackID == snap.trackID else { return }
                    self.store(image, for: snap.trackID)
                }
            }
        } else {
            MediaScripting.shared.localArtwork(for: snap.source) { [weak self] image in
                guard let self, let image, self.artworkTrackID == snap.trackID else { return }
                self.store(image, for: snap.trackID)
            }
        }
    }

    private func store(_ image: NSImage, for trackID: String) {
        if artworkCache.count > 24 { artworkCache.removeAll() }
        artworkCache[trackID] = image
        artwork = image
        palette = PaletteExtractor.palette(from: image)
    }

    // MARK: - Controles

    func togglePlayPause() {
        Debug.log("togglePlayPause chamado")
        guard let source else { return }
        MediaScripting.shared.playPause(source)
        scheduleRefresh()
    }

    /// Pula para uma fração da faixa. A posição local vai junto na hora, para
    /// a barra não pular de volta enquanto o player não confirma.
    func seek(toFraction fracao: Double) {
        Debug.log("seek para \(fracao)")
        guard let source, let snapshot else { return }
        let alvo = max(0, min(snapshot.duration, snapshot.duration * fracao))
        position = alvo
        anchorPosition = alvo
        anchorDate = Date()
        MediaScripting.shared.setPosition(alvo, on: source)
        scheduleRefresh()
    }

    func toggleShuffle() {
        guard let source, let snapshot else { return }
        MediaScripting.shared.setShuffle(!snapshot.shuffling, on: source)
        scheduleRefresh()
    }

    func next() {
        guard let source else { return }
        MediaScripting.shared.next(source)
        scheduleRefresh()
    }

    func previous() {
        guard let source else { return }
        MediaScripting.shared.previous(source)
        scheduleRefresh()
    }
}

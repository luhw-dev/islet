import Foundation
import Combine

/// Junta o que cada assistente informa de limite e mantém isso fresco.
///
/// Nada é consultado no lançamento: a primeira leitura só acontece quando a
/// página aparece. É o que evita o app pedir acesso ao chaveiro sozinho, antes
/// de a pessoa ter ido ver o uso.
@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var states: [UsageProvider: UsageState] = [:]
    @Published private(set) var isRefreshing = false
    /// Qual provedor está detalhado embaixo dos anéis.
    @Published var selected: UsageProvider = .claude

    /// De quanto em quanto tempo revisitamos as fontes depois da primeira vez.
    private static let intervalo: TimeInterval = 5 * 60

    private let settings: Settings
    private let sources: [UsageSource] = [ClaudeUsageSource(), CodexUsageSource()]
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var lastRefresh: Date?
    /// Quem só volta a ser consultado no botão. Hoje é o caso de quem teve o
    /// acesso ao chaveiro negado.
    private var bloqueados: Set<UsageProvider> = []
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings

        settings.$showUsage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] ativo in
                guard let self else { return }
                if ativo { self.refreshIfStale() } else { self.stopTimer() }
            }
            .store(in: &cancellables)
    }

    deinit { timer?.invalidate() }

    var providers: [UsageProvider] { UsageProvider.allCases }

    func state(for provider: UsageProvider) -> UsageState {
        states[provider] ?? .loading
    }

    /// Chamado toda vez que a página de uso entra em cena.
    func refreshIfStale(maxAge: TimeInterval = 120) {
        guard settings.showUsage else { return }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < maxAge { return }
        refresh()
    }

    /// `manual` é o toque no botão: aí até quem foi bloqueado entra de novo.
    func refresh(manual: Bool = false) {
        guard settings.showUsage, refreshTask == nil else { return }
        if manual { bloqueados.removeAll() }
        let fontes = sources.filter { !bloqueados.contains($0.provider) }
        guard !fontes.isEmpty else { return }
        isRefreshing = true

        refreshTask = Task { [sources = fontes] in
            await withTaskGroup(of: (UsageProvider, UsageState).self) { grupo in
                for fonte in sources {
                    grupo.addTask {
                        do {
                            return (fonte.provider, .ready(try await fonte.load()))
                        } catch let erro as UsageError {
                            if case .negado(let motivo) = erro {
                                return (fonte.provider, .unavailable("\(motivo) · toque em ↻"))
                            }
                            return (fonte.provider, .unavailable(erro.errorDescription ?? "Indisponível"))
                        } catch {
                            return (fonte.provider, .unavailable("Indisponível"))
                        }
                    }
                }
                for await (provider, state) in grupo {
                    states[provider] = state
                    if case .unavailable(let motivo) = state, motivo.contains("chaveiro") {
                        bloqueados.insert(provider)
                    } else {
                        bloqueados.remove(provider)
                    }
                }
            }

            lastRefresh = Date()
            isRefreshing = false
            refreshTask = nil
            ajustarSelecao()
            startTimer()
            Debug.log("uso atualizado: " + states.map { "\($0.key.rawValue)=\($0.value.snapshot.map { Int($0.headline) } ?? -1)" }.joined(separator: " "))
        }
    }

    /// Não deixa a página abrir num provedor sem número quando o outro tem.
    private func ajustarSelecao() {
        guard state(for: selected).snapshot == nil else { return }
        if let comDado = providers.first(where: { state(for: $0).snapshot != nil }) {
            selected = comDado
        }
    }

    private func startTimer() {
        guard timer == nil, settings.showUsage else { return }
        let novo = Timer(timeInterval: Self.intervalo, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(novo, forMode: .common)
        timer = novo
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

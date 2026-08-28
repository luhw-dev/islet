import Foundation

/// Um assistente cujo limite de uso a ilha acompanha.
enum UsageProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// A marca de verdade, desenhada como path (ver `BrandGlyph`).
    var glyph: BrandGlyph {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        }
    }
}

/// Uma janela de limite (a sessão de 5 h, a semana) num instante.
struct UsageWindow: Identifiable, Sendable {
    enum Kind: Sendable {
        case session
        case weekly
        /// Semana de um modelo só (o `/usage` chama de "current week (Fable)").
        case scoped
    }

    let kind: Kind
    let label: String
    /// 0…100.
    let percent: Double
    let resetsAt: Date?

    var id: String { label }

    /// Depois do reset o número guardado não vale mais nada: a janela virou.
    var isExpired: Bool {
        guard let resetsAt else { return false }
        return resetsAt < Date()
    }
}

/// Leitura completa de um provedor.
struct UsageSnapshot: Sendable {
    let provider: UsageProvider
    let windows: [UsageWindow]
    /// "pro", "max"… quando a fonte informa.
    let plan: String?
    /// Quando o número foi *medido*, e não quando foi lido. O Codex só publica
    /// limite enquanto roda, então isso pode ser de dias atrás.
    let measuredAt: Date

    /// O que vai no anel: a janela mais apertada.
    var headline: Double { windows.map(\.percent).max() ?? 0 }

    var age: TimeInterval { max(0, Date().timeIntervalSince(measuredAt)) }

    /// Velha o bastante para valer a pena dizer de quando é. O Codex publica
    /// limite só enquanto roda, então quase toda leitura dele cai aqui.
    var isDated: Bool { age > 15 * 60 }

    /// Velha demais para ser lida como o estado de agora — ou de uma janela que
    /// já virou. Aí o número aparece esmaecido.
    var isStale: Bool {
        if windows.contains(where: \.isExpired) { return true }
        return age > 6 * 3600
    }
}

/// Por que um provedor não tem número para mostrar. A mensagem vai para a tela,
/// então é curta e diz o que fazer.
enum UsageError: LocalizedError {
    case semCredencial(String)
    case indisponivel(String)
    /// A pessoa recusou o acesso ao chaveiro. Vale um caso próprio: insistir
    /// sozinho nisso vira um desfile de diálogos do sistema.
    case negado(String)

    var errorDescription: String? {
        switch self {
        case .semCredencial(let motivo), .indisponivel(let motivo), .negado(let motivo):
            return motivo
        }
    }
}

enum UsageState {
    case loading
    case ready(UsageSnapshot)
    case unavailable(String)

    var snapshot: UsageSnapshot? {
        if case .ready(let snapshot) = self { return snapshot }
        return nil
    }
}

protocol UsageSource: Sendable {
    var provider: UsageProvider { get }
    func load() async throws -> UsageSnapshot
}

// MARK: - Peças compartilhadas pelas fontes

enum UsageParsing {
    /// ISO-8601 com fração de segundo de tamanho variável (a Anthropic manda
    /// seis casas, que o parser padrão recusa em algumas versões).
    static func date(fromISO texto: String) -> Date? {
        let comFracao = ISO8601DateFormatter()
        comFracao.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let data = comFracao.date(from: texto) { return data }

        let simples = ISO8601DateFormatter()
        simples.formatOptions = [.withInternetDateTime]
        if let data = simples.date(from: texto) { return data }

        // Última tentativa: corta a fração à mão e tenta de novo.
        guard let ponto = texto.firstIndex(of: "."),
              let fim = texto[ponto...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        else { return nil }
        var recortado = texto
        recortado.removeSubrange(ponto..<fim)
        return simples.date(from: recortado)
    }

    /// Nome curto da janela a partir da duração declarada pela fonte.
    static func label(forWindowMinutes minutos: Int) -> (UsageWindow.Kind, String) {
        if minutos <= 360 { return (.session, "Sessão") }
        if minutos <= 1440 { return (.weekly, "Dia") }
        return (.weekly, "Semana")
    }
}

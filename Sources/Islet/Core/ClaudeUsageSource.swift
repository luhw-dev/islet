import Foundation
import Security

/// Uso do Claude Code: token OAuth do chaveiro + endpoint que alimenta o
/// `/usage` do próprio CLI.
///
/// Não renovamos o token: quem faz isso é o Claude Code. O que guardamos é a
/// leitura — ver `ClaudeTokenStore`.
struct ClaudeUsageSource: UsageSource {
    let provider: UsageProvider = .claude

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    func load() async throws -> UsageSnapshot {
        var (data, status) = try await Self.consultar(
            token: try await ClaudeTokenStore.shared.current())

        if status == 401 || status == 403 {
            // O token guardado caiu antes da validade que ele mesmo anunciava
            // (o Claude Code pode ter trocado a credencial). Vale reler o
            // chaveiro uma vez — e só uma, para não virar laço de diálogo.
            (data, status) = try await Self.consultar(
                token: try await ClaudeTokenStore.shared.current(reloading: true))
        }

        switch status {
        case 200:
            break
        case 401, 403:
            throw UsageError.semCredencial("Sessão expirada — abra o Claude Code")
        default:
            throw UsageError.indisponivel("Erro \(status)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.indisponivel("Resposta ilegível")
        }
        return try Self.snapshot(from: json)
    }

    private static func consultar(token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageError.indisponivel("Sem conexão")
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.indisponivel("Resposta inesperada")
        }
        return (data, http.statusCode)
    }

    // MARK: - Credencial

    /// Token e até quando ele vale, na ordem em que o Claude Code guarda.
    static func credencial() throws -> (token: String, validoAte: Date?) {
        do {
            return try credencialDoChaveiro()
        } catch let erro as UsageError {
            // Recusa é decisão da pessoa, e não falta de credencial: sobe como
            // está para o monitor parar de tentar sozinho.
            if case .negado = erro { throw erro }
        } catch {}
        // O Claude Code cai para um arquivo quando não tem chaveiro (containers,
        // sessões remotas). Se ele existir, serve igual.
        if let doArquivo = credencialDoArquivo() { return doArquivo }
        throw UsageError.semCredencial("Faça login no Claude Code")
    }

    private static func credencialDoChaveiro() throws -> (token: String, validoAte: Date?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var resultado: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &resultado)
        guard status == errSecSuccess, let data = resultado as? Data else {
            if status == errSecUserCanceled || status == errSecAuthFailed
                || status == errSecInteractionNotAllowed {
                throw UsageError.negado("Acesso ao chaveiro negado")
            }
            throw UsageError.semCredencial("Faça login no Claude Code")
        }
        guard let credencial = credencial(emDados: data) else {
            throw UsageError.semCredencial("Credencial em formato desconhecido")
        }
        return credencial
    }

    private static func credencialDoArquivo() -> (token: String, validoAte: Date?)? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return credencial(emDados: data)
    }

    private static func credencial(emDados data: Data) -> (token: String, validoAte: Date?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        // `expiresAt` vem em milissegundos.
        let validade = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return (token, validade)
    }

    // MARK: - Resposta

    private static func snapshot(from json: [String: Any]) throws -> UsageSnapshot {
        var janelas = windowsFromLimits(json)
        // Formato antigo, caso `limits` suma da resposta um dia.
        if janelas.isEmpty { janelas = windowsFromLegacyFields(json) }
        guard !janelas.isEmpty else { throw UsageError.indisponivel("Sem dados de limite") }

        return UsageSnapshot(
            provider: .claude,
            windows: janelas,
            plan: nil,
            measuredAt: Date())
    }

    /// A lista `limits` é o que o `/usage` desenha: sessão de 5 h, semana toda e
    /// semana por modelo. Ficamos com as duas primeiras — é o que cabe na ilha.
    private static func windowsFromLimits(_ json: [String: Any]) -> [UsageWindow] {
        guard let limites = json["limits"] as? [[String: Any]] else { return [] }

        func janela(kind: UsageWindow.Kind, procurando alvo: String, rotulo: String) -> UsageWindow? {
            guard let entrada = limites.first(where: { $0["kind"] as? String == alvo }),
                  let percentual = (entrada["percent"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (entrada["resets_at"] as? String).flatMap(UsageParsing.date(fromISO:))
            return UsageWindow(kind: kind, label: rotulo, percent: percentual, resetsAt: reset)
        }

        // A terceira é a semana de um modelo específico; o nome dele vem no
        // `scope`, então o rótulo sai da resposta em vez de ser fixo aqui.
        let porModelo = limites.first { $0["kind"] as? String == "weekly_scoped" }
        let modelo = ((porModelo?["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String

        return [
            janela(kind: .session, procurando: "session", rotulo: "Sessão"),
            janela(kind: .weekly, procurando: "weekly_all", rotulo: "Semana"),
            janela(kind: .scoped, procurando: "weekly_scoped", rotulo: modelo.map { "Semana · \($0)" } ?? "Semana · modelo")
        ].compactMap { $0 }
    }

    private static func windowsFromLegacyFields(_ json: [String: Any]) -> [UsageWindow] {
        func janela(_ chave: String, kind: UsageWindow.Kind, rotulo: String) -> UsageWindow? {
            guard let bloco = json[chave] as? [String: Any],
                  let percentual = (bloco["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (bloco["resets_at"] as? String).flatMap(UsageParsing.date(fromISO:))
            return UsageWindow(kind: kind, label: rotulo, percent: percentual, resetsAt: reset)
        }

        return [
            janela("five_hour", kind: .session, rotulo: "Sessão"),
            janela("seven_day", kind: .weekly, rotulo: "Semana")
        ].compactMap { $0 }
    }
}

/// Segura o token entre consultas.
///
/// O item do chaveiro é do Claude Code, e o macOS pergunta a cada leitura feita
/// por outro app enquanto ele não estiver na lista de confiança do item — lista
/// que se perde quando o Claude Code regrava a credencial ao renovar. Lendo uma
/// vez por validade do token, e não a cada consulta, o diálogo deixa de ser
/// recorrente mesmo quando isso acontece.
actor ClaudeTokenStore {
    static let shared = ClaudeTokenStore()

    private var token: String?
    private var validoAte: Date?

    /// Sem validade anunciada, guarda por meia hora — o bastante para não
    /// reler a cada atualização, pouco para não segurar um token morto.
    private static let validadePadrao: TimeInterval = 30 * 60
    /// Margem antes do vencimento: token que expira no meio da consulta não
    /// serve para nada.
    private static let margem: TimeInterval = 60

    func current(reloading: Bool = false) throws -> String {
        if !reloading, let token, let validoAte, validoAte.timeIntervalSinceNow > Self.margem {
            return token
        }
        let credencial = try ClaudeUsageSource.credencial()
        token = credencial.token
        validoAte = credencial.validoAte ?? Date().addingTimeInterval(Self.validadePadrao)
        return credencial.token
    }
}

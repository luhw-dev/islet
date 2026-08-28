import Foundation

/// Uso do Codex. Não há endpoint público de quota, mas o próprio CLI grava o
/// que o servidor devolve: cada evento `token_count` do rollout traz
/// `rate_limits`. Lemos o mais recente.
///
/// A consequência é que o número só anda quando o Codex roda — por isso a
/// leitura carrega a data da medição, e a ilha avisa quando ela envelhece.
struct CodexUsageSource: UsageSource {
    let provider: UsageProvider = .codex

    /// Quantos rollouts vale a pena abrir: sessão curta pode terminar sem
    /// nenhum `token_count`, então o mais recente nem sempre tem resposta.
    private static let maxArquivos = 6
    /// Só o fim do arquivo interessa, e ele passa fácil de 100 MB.
    private static let tailBytes = 512 * 1024

    func load() async throws -> UsageSnapshot {
        let raiz = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: raiz.path) else {
            throw UsageError.semCredencial("Codex não encontrado")
        }

        let arquivos = Self.rolloutsRecentes(em: raiz)
        guard !arquivos.isEmpty else {
            throw UsageError.indisponivel("Nenhuma sessão do Codex")
        }

        var melhor: (quando: Date, limites: [String: Any])?
        for arquivo in arquivos {
            guard let evento = Self.ultimoEventoDeLimite(em: arquivo) else { continue }
            if melhor == nil || evento.quando > melhor!.quando { melhor = evento }
        }
        guard let melhor else {
            throw UsageError.indisponivel("Rode o Codex para atualizar")
        }

        let janelas = Self.janelas(de: melhor.limites)
        guard !janelas.isEmpty else {
            throw UsageError.indisponivel("Sem dados de limite")
        }

        return UsageSnapshot(
            provider: .codex,
            windows: janelas,
            plan: melhor.limites["plan_type"] as? String,
            measuredAt: melhor.quando)
    }

    // MARK: - Arquivos

    /// Os rollouts ficam em `sessions/AAAA/MM/DD/`. Descer pelos nomes em ordem
    /// decrescente chega nos dias recentes sem varrer o histórico inteiro.
    private static func rolloutsRecentes(em raiz: URL) -> [URL] {
        let fm = FileManager.default

        func pastas(_ url: URL) -> [URL] {
            let conteudo = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            return conteudo
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }

        var encontrados: [URL] = []
        busca: for ano in pastas(raiz) {
            for mes in pastas(ano) {
                for dia in pastas(mes) {
                    let conteudo = (try? fm.contentsOfDirectory(
                        at: dia,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles])) ?? []
                    encontrados += conteudo.filter { $0.pathExtension == "jsonl" }
                    if encontrados.count >= maxArquivos * 3 { break busca }
                }
            }
        }

        return encontrados
            .sorted { modificado(em: $0) > modificado(em: $1) }
            .prefix(maxArquivos)
            .map { $0 }
    }

    private static func modificado(em url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private static func ultimoEventoDeLimite(em url: URL) -> (quando: Date, limites: [String: Any])? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let fim = try? handle.seekToEnd() else { return nil }
        let inicio = fim > UInt64(tailBytes) ? fim - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: inicio)
        guard let dados = try? handle.readToEnd(),
              let texto = String(data: dados, encoding: .utf8) else { return nil }

        for linha in texto.split(separator: "\n").reversed() {
            guard linha.contains("\"rate_limits\"") else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: Data(linha.utf8)) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let limites = payload["rate_limits"] as? [String: Any] else { continue }
            let quando = (json["timestamp"] as? String).flatMap(UsageParsing.date(fromISO:))
                ?? modificado(em: url)
            return (quando, limites)
        }
        return nil
    }

    // MARK: - Conteúdo

    /// `primary` e `secondary` trocam de significado conforme o plano: às vezes
    /// a primária é a janela de 5 h, às vezes já é a semanal. Quem decide o
    /// rótulo é a duração declarada, não a posição.
    private static func janelas(de limites: [String: Any]) -> [UsageWindow] {
        ["primary", "secondary"]
            .compactMap { janela(limites[$0] as? [String: Any]) }
            .sorted { $0.kind == .session && $1.kind != .session }
    }

    private static func janela(_ bloco: [String: Any]?) -> UsageWindow? {
        guard let bloco,
              let percentual = (bloco["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let minutos = (bloco["window_minutes"] as? NSNumber)?.intValue ?? 0
        let (kind, rotulo) = UsageParsing.label(forWindowMinutes: minutos)
        return UsageWindow(kind: kind, label: rotulo, percent: percentual, resetsAt: reset(bloco["resets_at"]))
    }

    /// Já veio como segundos desde 1970 e como texto ISO em versões diferentes.
    private static func reset(_ valor: Any?) -> Date? {
        if let numero = valor as? NSNumber { return Date(timeIntervalSince1970: numero.doubleValue) }
        if let texto = valor as? String { return UsageParsing.date(fromISO: texto) }
        return nil
    }
}

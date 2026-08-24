import Foundation

/// Atalhos para desenvolver sem depender de um segundo monitor ou do mouse.
///   ISLET_FORCE_SIMULATED=1  desenha a ilha falsa mesmo na tela com notch
///   ISLET_OPEN_ON_LAUNCH=1   já abre expandida ao iniciar
enum Debug {
    /// stderr não tem buffer: dá para ler o log com o app ainda rodando.
    /// Caminho opcional de log. Aberto pelo Finder o app não tem stderr, e é
    /// justamente nesse modo que as permissões se comportam de verdade.
    static let logFile = ProcessInfo.processInfo.environment["ISLET_LOG_FILE"]

    static func log(_ mensagem: String) {
        guard traceInput || logFile != nil else { return }
        let linha = "[islet] \(mensagem)\n"
        fputs(linha, stderr)
        guard let logFile, let dados = linha.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(dados)
            try? handle.close()
        } else {
            try? dados.write(to: URL(fileURLWithPath: logFile))
        }
    }

    static let forceSimulated = ProcessInfo.processInfo.environment["ISLET_FORCE_SIMULATED"] == "1"
    static let openOnLaunch = ProcessInfo.processInfo.environment["ISLET_OPEN_ON_LAUNCH"] == "1"
    static let staticEqualizer = ProcessInfo.processInfo.environment["ISLET_STATIC_EQ"] == "1"
    static let traceInput = ProcessInfo.processInfo.environment["ISLET_TRACE_INPUT"] == "1"
    static let noBrightness = ProcessInfo.processInfo.environment["ISLET_NO_BRIGHTNESS"] == "1"
    /// Caminhos separados por vírgula para semear a prateleira ao abrir.
    static let testShelf: [URL] = (ProcessInfo.processInfo.environment["ISLET_TEST_SHELF"] ?? "")
        .split(separator: ",")
        .map { URL(fileURLWithPath: String($0)) }
    /// Fração (0...1) para um seek automático alguns segundos após abrir.
    static let testSeek = ProcessInfo.processInfo.environment["ISLET_TEST_SEEK"].flatMap(Double.init)
}

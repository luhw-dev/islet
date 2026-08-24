import AppKit
import Combine

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var name: String { url.lastPathComponent }
}

/// A prateleira de arquivos, compartilhada por todas as ilhas.
///
/// Uma por tela seria pior: você solta um arquivo no monitor externo e ele
/// some quando você olha para o notebook. E os caminhos sobrevivem ao fechar
/// o app — quem estaciona um arquivo aqui espera reencontrá-lo, não descobrir
/// que sumiu (ou pior, achar que o app o moveu).
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let defaults = UserDefaults.standard
    private static let chave = "shelfPaths"

    init() {
        let caminhos = defaults.stringArray(forKey: Self.chave) ?? []
        // Arquivo apagado ou movido desde a última sessão não volta como item
        // fantasma que não abre.
        items = caminhos
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { ShelfItem(url: $0) }
        Debug.log("prateleira restaurada: \(items.count) de \(caminhos.count) caminhos")
    }

    func add(_ urls: [URL]) {
        let conhecidos = Set(items.map(\.url))
        let novos = urls.filter { !conhecidos.contains($0) }.map { ShelfItem(url: $0) }
        guard !novos.isEmpty else { return }
        items.append(contentsOf: novos)
        salvar()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        salvar()
    }

    func clear() {
        items.removeAll()
        salvar()
    }

    private func salvar() {
        defaults.set(items.map(\.url.path), forKey: Self.chave)
    }
}

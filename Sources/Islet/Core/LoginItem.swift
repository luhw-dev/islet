import Foundation
import ServiceManagement

/// Abrir junto com o sistema.
///
/// A fonte de verdade é o próprio macOS (`SMAppService.status`), não um ajuste
/// nosso: a pessoa pode desligar isso em Ajustes do Sistema › Itens de Início,
/// e um espelho em UserDefaults ficaria mentindo.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Devolve o erro em vez de engolir: registrar falha quando o app está em
    /// lugar volátil (montagem de DMG, Downloads em quarentena), e o silêncio
    /// viraria "marquei e não funcionou".
    @discardableResult
    static func setEnabled(_ ligado: Bool) -> Error? {
        do {
            if ligado {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error
        }
    }
}

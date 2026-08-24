import AppKit

/// Ícone na barra de menus (o app não aparece no Dock).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let app: AppModel
    private let onRebuild: () -> Void

    init(app: AppModel, onRebuild: @escaping () -> Void) {
        self.app = app
        self.onRebuild = onRebuild
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.image = NSImage(
            systemSymbolName: "capsule.fill",
            accessibilityDescription: "Islet"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let notched = NSScreen.screens.filter { IslandGeometry.physicalNotchSize(of: $0) != nil }.count
        let header = NSMenuItem(
            title: "\(NSScreen.screens.count) tela(s) · \(notched) com notch",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for modo in ActivationMode.allCases {
            let entry = NSMenuItem(title: modo.title, action: #selector(setActivation(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = modo.rawValue
            entry.state = app.settings.activation == modo ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let simulate = NSMenuItem(
            title: "Ilha simulada em telas sem notch",
            action: #selector(toggleSimulate),
            keyEquivalent: ""
        )
        simulate.target = self
        simulate.state = app.settings.simulateOnExternal ? .on : .off
        menu.addItem(simulate)

        let notch = NSMenuItem(
            title: "Usar o notch do MacBook",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        )
        notch.target = self
        notch.state = app.settings.showOnNotchedScreen ? .on : .off
        menu.addItem(notch)

        let hud = NSMenuItem(
            title: "Mostrar volume e brilho na ilha",
            action: #selector(toggleHUD),
            keyEquivalent: ""
        )
        hud.target = self
        hud.state = app.settings.showSystemHUD ? .on : .off
        menu.addItem(hud)

        let teclas = NSMenuItem(
            title: app.mediaKeys.needsPermission
                ? "Assumir teclas de volume e brilho (falta \(MediaKeyTap.missingPermissions.joined(separator: " e ")))"
                : "Assumir teclas de volume e brilho",
            action: #selector(toggleMediaKeys),
            keyEquivalent: ""
        )
        teclas.target = self
        teclas.state = app.settings.interceptMediaKeys ? .on : .off
        menu.addItem(teclas)

        if app.mediaKeys.needsPermission {
            let ajustes = NSMenuItem(
                title: "Abrir Ajustes de Privacidade…",
                action: #selector(abrirPermissao),
                keyEquivalent: ""
            )
            ajustes.target = self
            menu.addItem(ajustes)
        }

        let halo = NSMenu()
        for estilo in HaloStyle.allCases {
            let item = NSMenuItem(title: estilo.title, action: #selector(setHalo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = estilo.rawValue
            item.state = app.settings.haloStyle == estilo ? .on : .off
            halo.addItem(item)
        }
        let haloItem = NSMenuItem(title: "Desfoque ao redor", action: nil, keyEquivalent: "")
        haloItem.submenu = halo
        menu.addItem(haloItem)

        let haptico = NSMenuItem(
            title: "Retorno tátil no trackpad",
            action: #selector(toggleHaptics),
            keyEquivalent: ""
        )
        haptico.target = self
        haptico.state = app.settings.hapticFeedback ? .on : .off
        menu.addItem(haptico)

        let announce = NSMenuItem(
            title: "Avisar quando a música mudar",
            action: #selector(toggleAnnounce),
            keyEquivalent: ""
        )
        announce.target = self
        announce.state = app.settings.announceTrackChanges ? .on : .off
        menu.addItem(announce)

        menu.addItem(.separator())

        let widths: [(String, Double)] = [("Estreita", 150), ("Média", 190), ("Larga", 230)]
        let widthMenu = NSMenu()
        for (nome, valor) in widths {
            let entry = NSMenuItem(title: nome, action: #selector(setWidth(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = valor
            entry.state = abs(app.settings.simulatedWidth - valor) < 1 ? .on : .off
            widthMenu.addItem(entry)
        }
        let widthItem = NSMenuItem(title: "Largura da ilha simulada", action: nil, keyEquivalent: "")
        widthItem.submenu = widthMenu
        menu.addItem(widthItem)

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Recarregar telas", action: #selector(reload), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let quit = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func setActivation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let modo = ActivationMode(rawValue: raw) else { return }
        app.settings.activation = modo
    }

    @objc private func toggleSimulate() {
        app.settings.simulateOnExternal.toggle()
    }

    @objc private func toggleNotch() {
        app.settings.showOnNotchedScreen.toggle()
    }

    @objc private func toggleAnnounce() {
        app.settings.announceTrackChanges.toggle()
    }

    @objc private func setHalo(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let estilo = HaloStyle(rawValue: raw) else { return }
        app.settings.haloStyle = estilo
    }

    @objc private func toggleHaptics() {
        app.settings.hapticFeedback.toggle()
    }

    @objc private func abrirPermissao() {
        app.mediaKeys.abrirAjustesDePermissao()
    }

    @objc private func toggleMediaKeys() {
        app.settings.interceptMediaKeys.toggle()
    }

    @objc private func toggleHUD() {
        app.settings.showSystemHUD.toggle()
    }

    @objc private func setWidth(_ sender: NSMenuItem) {
        guard let valor = sender.representedObject as? Double else { return }
        app.settings.simulatedWidth = valor
        onRebuild()
    }

    @objc private func reload() {
        onRebuild()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

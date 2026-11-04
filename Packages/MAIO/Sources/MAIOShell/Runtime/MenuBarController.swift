import AppKit
import MAIOCore
import MAIOKit

/// 菜单栏图标与菜单。菜单每次打开时重新生成，保证状态最新。
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var controller: MAIOAppController?

    init(controller: MAIOAppController) {
        self.controller = controller
        super.init()
        item.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let controller else { return }
        if controller.runtime.input.status != .running {
            let warning = NSMenuItem(title: "⚠️ 需要辅助功能权限，快捷键未生效", action: #selector(openPermissions), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }
        let host = controller.runtime.host
        for manifest in host.manifests {
            let entry = NSMenuItem(title: manifest.displayName, action: nil, keyEquivalent: "")
            entry.image = NSImage(systemSymbolName: manifest.symbol, accessibilityDescription: nil)
            entry.state = host.state(of: manifest.id) == .running ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(updateItem(controller.updater))
        menu.addItem(makeItem("设置…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("退出 MAIO", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    /// 下载好新版本时显示"安装更新"，否则"检查更新…"
    private func updateItem(_ updater: Updater) -> NSMenuItem {
        switch updater.state {
        case let .ready(prepared):
            makeItem("安装更新 \(prepared.release.version)…", #selector(checkForUpdates), key: "")
        case let .downloading(version):
            NSMenuItem(title: "正在下载更新 \(version)…", action: nil, keyEquivalent: "")
        case .checking:
            NSMenuItem(title: "正在检查更新…", action: nil, keyEquivalent: "")
        default:
            makeItem("检查更新…", #selector(checkForUpdates), key: "")
        }
    }

    @objc private func checkForUpdates() {
        guard let controller else { return }
        Task { await controller.updater.check(userInitiated: true) }
    }

    @objc private func openSettings() {
        controller?.showSettings()
    }

    @objc private func openPermissions() {
        controller?.showSettings(pane: .permissions)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

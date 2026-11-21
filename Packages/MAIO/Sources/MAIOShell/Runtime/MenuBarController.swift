import AppKit
import MAIOCore
import MAIOKit
import SwiftUI

/// 菜单栏图标与菜单。菜单每次打开时重新生成，保证状态最新。
/// 内容：（缺权限时的提示）→ 各功能的菜单视图 → 检查更新、设置、退出。不再列出功能开关（在设置里管理）。
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
        let views = menuBarViews(controller.runtime.host)
        views.forEach(menu.addItem)
        if !views.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(updateItem(controller.updater))
        menu.addItem(makeItem("设置…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("退出 MAIO", #selector(quit), key: "q"))
    }

    /// 各功能放进菜单的视图（ADR-0028），例如外接显示器的亮度滑块。功能返回 nil 时不显示
    private func menuBarViews(_ host: FeatureHost) -> [NSMenuItem] {
        host.manifests.compactMap { manifest in
            guard host.state(of: manifest.id) == .running,
                  let view = host.feature(manifest.id)?.makeMenuBarView()
            else { return nil }
            let hosting = NSHostingView(rootView: view.frame(width: Self.menuViewWidth))
            hosting.frame.size = hosting.fittingSize
            let menuItem = NSMenuItem()
            menuItem.view = hosting
            return menuItem
        }
    }

    private static let menuViewWidth: CGFloat = 280

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
        controller?.showSettings(pane: .general)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

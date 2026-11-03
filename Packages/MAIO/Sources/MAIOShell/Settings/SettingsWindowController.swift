import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

enum SettingsPane: Hashable {
    case general
    case shortcuts
    case permissions
    case systemShortcuts
    case feature(FeatureID)
}

/// 设置窗口导航状态（窗口外部可以切换页面）。
@MainActor
@Observable
final class SettingsNavigation {
    var selection: SettingsPane? = .shortcuts
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let minimumSize = CGSize(width: 760, height: 500)
    private weak var controller: MAIOAppController?
    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    init(controller: MAIOAppController) {
        self.controller = controller
    }

    func show(pane: SettingsPane?) {
        if let pane {
            navigation.selection = pane
        }
        if window == nil, let controller {
            window = makeWindow(controller)
        }
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // 从菜单栏菜单打开时，菜单还没关闭、激活策略刚切换，立即 activate 会被系统忽略，
        // 结果窗口在最前却没有焦点。等到下一轮事件循环（菜单已关闭）再激活一次。
        DispatchQueue.main.async {
            // macOS 14 起 NSApp.activate() 是"协作式"请求，从菜单栏菜单发起时会被系统拒绝（实测）。
            // 用户明确点了"设置"，这里需要强制激活。通过协议调用旧接口，避免弃用警告（警告即错误）。
            AppActivation.activateForcibly()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_: Notification) {
        // 关闭设置窗口后回到纯菜单栏模式（不显示 Dock 图标）
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow(_ controller: MAIOAppController) -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsRootView(controller: controller, navigation: navigation))
        // 只让 SwiftUI 决定最小尺寸，窗口大小由用户调整并自动记忆
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.contentViewController = hosting
        window.setContentSize(CGSize(width: 880, height: 600))
        window.title = "MAIO 设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentMinSize = Self.minimumSize
        window.setFrameAutosaveName("MAIOSettings")
        // 记忆的尺寸可能来自旧版本，小于最小尺寸时重置
        let size = window.contentLayoutRect.size
        if size.width < Self.minimumSize.width || size.height < Self.minimumSize.height {
            window.setContentSize(CGSize(width: 880, height: 600))
            window.center()
        }
        return window
    }
}

struct SettingsRootView: View {
    let controller: MAIOAppController
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                Section {
                    Label("通用", systemImage: "gearshape").tag(SettingsPane.general)
                    Label("快捷键", systemImage: "keyboard").tag(SettingsPane.shortcuts)
                    Label("系统快捷键", systemImage: "globe").tag(SettingsPane.systemShortcuts)
                    Label("权限", systemImage: "lock.shield").tag(SettingsPane.permissions)
                }
                Section("功能") {
                    ForEach(controller.runtime.host.manifests) { manifest in
                        Label(manifest.displayName, systemImage: manifest.symbol)
                            .tag(SettingsPane.feature(manifest.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    @ViewBuilder private var detail: some View {
        switch navigation.selection ?? .general {
        case .general: GeneralPane(controller: controller)
        case .shortcuts: ShortcutsPane(controller: controller)
        case .permissions: PermissionsPane(controller: controller)
        case .systemShortcuts: SystemShortcutsPane(controller: controller)
        case let .feature(id): FeaturePane(controller: controller, featureID: id)
        }
    }
}

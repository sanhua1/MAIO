import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// 快捷键页的分类（横向标签）。
enum ShortcutCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    /// 调用 MAIO 自己的功能（截图、翻译、剪贴板、窗口切换……）
    case features = "MAIO 功能"
    /// 打开某个 App
    case apps = "打开 App"
    /// 其他动作：网址、Shell、AppleScript、快捷指令、发送按键
    case actions = "其他动作"

    var id: Self {
        self
    }

    static let systemFeature: FeatureID = "system"
    static let openApp: CommandID = "system.openApp"

    /// 命令属于哪一类（owner：提供这个命令的功能）
    static func of(command: CommandID, owner: FeatureID?) -> ShortcutCategory {
        guard owner == systemFeature else { return .features }
        return command == openApp ? .apps : .actions
    }

    func contains(_ category: ShortcutCategory) -> Bool {
        self == .all || self == category
    }
}

/// 一条绑定在界面上怎么显示：图标、标题。
@MainActor
struct BindingPresentation {
    let binding: CommandBinding
    let manifest: FeatureManifest?
    let descriptor: CommandDescriptor?

    init(binding: CommandBinding, catalog: [FeatureManifest]) {
        self.binding = binding
        manifest = catalog.first { $0.commands.contains { $0.id == binding.command } }
        descriptor = manifest?.commands.first { $0.id == binding.command }
    }

    var category: ShortcutCategory {
        ShortcutCategory.of(command: binding.command, owner: manifest?.id)
    }

    /// 打开 App 的绑定没有备注时显示"打开 <App 名>"
    var title: String {
        if let title = binding.title {
            return title
        }
        if binding.command == ShortcutCategory.openApp, let url = appURL {
            return "打开 " + FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return descriptor?.title ?? binding.command.rawValue
    }

    var appURL: URL? {
        guard binding.command == ShortcutCategory.openApp else { return nil }
        return binding.arguments["app"]?.stringValue.flatMap(Self.applicationURL)
    }

    /// bundle ID 或 .app 路径 → App 地址
    static func applicationURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let path = (trimmed as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path) ? URL(filePath: path) : nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
    }

    /// 和命令相关的 App（用它的图标）
    private var relatedAppURL: URL? {
        switch binding.command.rawValue {
        case "system.openApp": appURL
        case "system.runShell": NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        case "system.runAppleScript": NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScriptEditor2")
        case "system.runShortcut": NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
        case "system.openURL": urlTarget
        default: nil
        }
    }

    /// 打开的是本地文件或文件夹时用它的图标；网址用地球图标
    private var urlTarget: URL? {
        guard let value = binding.arguments["url"]?.stringValue, !value.contains("://") else { return nil }
        let path = (value as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path) ? URL(filePath: path) : nil
    }

    var icon: some View {
        BindingIcon(appURL: relatedAppURL, symbol: symbol, isFeature: category == .features)
    }

    private var symbol: String {
        switch binding.command.rawValue {
        case "system.openApp": "app.dashed"
        case "system.openURL": "globe"
        case "system.sendKeys": "keyboard"
        default: manifest?.symbol ?? "command"
        }
    }
}

/// 行首图标：相关 App 的图标；MAIO 功能用功能的符号（彩色底）；其他用灰色符号。
struct BindingIcon: View {
    let appURL: URL?
    let symbol: String
    let isFeature: Bool
    static let size: CGFloat = 24

    var body: some View {
        if let appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: Self.size, height: Self.size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFeature ? Color.white : Color.secondary)
                .frame(width: Self.size - 2, height: Self.size - 2)
                .background(
                    isFeature ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 6),
                )
                .frame(width: Self.size, height: Self.size)
        }
    }
}

/// 绑定的状态徽标：不可用 / 冲突 / 覆盖系统快捷键（快捷键页和功能页共用）
struct BindingStatus: View {
    let controller: MAIOAppController
    let binding: CommandBinding

    var body: some View {
        if !controller.runtime.commandBus.isAvailable(binding.command) {
            StatusBadge("不可用", tone: .warning).help("提供该命令的功能未启用")
        } else if !controller.runtime.bindings.conflicts(with: binding).isEmpty {
            StatusBadge("冲突", tone: .negative).help("另一个已启用的绑定使用了相同的快捷键")
        } else if let reserved = controller.featureReservations(for: binding).first {
            StatusBadge("部分 App 中被占用", tone: .warning).help("被\(reserved)占用，在那里不会触发这个绑定")
        } else if let system = controller.systemConflicts(for: binding).first {
            Button {
                controller.showSettings(pane: .systemShortcuts)
            } label: {
                StatusBadge("覆盖系统快捷键", tone: .neutral)
            }
            .buttonStyle(.plain)
            .help("这个组合原本是系统快捷键「\(system.info.name)」，MAIO 运行时由 MAIO 接管。点击查看")
        }
    }
}

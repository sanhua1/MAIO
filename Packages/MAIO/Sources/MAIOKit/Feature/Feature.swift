import os
import SwiftUI

/// 功能模块协议。实现规范见 docs/FEATURE_GUIDE.md。
@MainActor
public protocol Feature: AnyObject {
    /// 静态元信息：宿主不实例化功能就能读取（设置页、权限引导、绑定编辑器都用它）。
    static var manifest: FeatureManifest { get }

    init(context: any FeatureContext)

    /// 启用：注册命令、注册过滤器、开始监听。抛错时宿主会隔离该功能，不影响其他功能。
    func activate() async throws
    /// 停用：释放全部资源。命令、过滤器、键盘会话由宿主自动清理，其余（窗口、Task、监听）由功能自己释放。
    func deactivate() async

    /// 设置页（可选），显示在统一设置窗口中。
    func makeSettingsView() -> AnyView?
}

public extension Feature {
    func makeSettingsView() -> AnyView? {
        nil
    }
}

public struct FeatureManifest: Sendable, Identifiable {
    public let id: FeatureID
    public let displayName: String
    /// SF Symbol 名称
    public let symbol: String
    public let summary: String
    public let requiredPermissions: Set<Permission>
    public let commands: [CommandDescriptor]
    public let defaultBindings: [DefaultBinding]
    public let enabledByDefault: Bool

    public init(
        id: FeatureID,
        displayName: String,
        symbol: String,
        summary: String,
        requiredPermissions: Set<Permission> = [],
        commands: [CommandDescriptor] = [],
        defaultBindings: [DefaultBinding] = [],
        enabledByDefault: Bool = true,
    ) {
        self.id = id
        self.displayName = displayName
        self.symbol = symbol
        self.summary = summary
        self.requiredPermissions = requiredPermissions
        self.commands = commands
        self.defaultBindings = defaultBindings
        self.enabledByDefault = enabledByDefault
    }
}

/// 功能能接触到的全部能力。功能不得使用任何全局单例，一切都从这里获取。
@MainActor
public protocol FeatureContext: AnyObject {
    var featureID: FeatureID { get }
    var commands: any CommandRegistrar { get }
    var input: any InputService { get }
    var settings: any SettingsService { get }
    var storage: any StorageService { get }
    var secrets: any SecretService { get }
    var permissions: any PermissionService { get }
    var overlay: any OverlayService { get }
    var events: any SystemEventService { get }
    /// 快捷键占用查询与登记（ADR-0018）
    var shortcuts: any ShortcutDirectory { get }
    var logger: Logger { get }
}

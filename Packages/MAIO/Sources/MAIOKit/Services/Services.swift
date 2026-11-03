import Foundation

/// 系统权限。
public enum Permission: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// 辅助功能：拦截/修改键盘鼠标事件、读取和控制其他 App 的窗口
    case accessibility
    /// 输入监控：只读监听键盘事件
    case inputMonitoring
    /// 屏幕录制：截图、窗口缩略图
    case screenRecording

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .accessibility: "辅助功能"
        case .inputMonitoring: "输入监控"
        case .screenRecording: "屏幕与系统录音"
        }
    }
}

@MainActor
public protocol PermissionService: AnyObject {
    func isGranted(_ permission: Permission) -> Bool
    /// 触发系统授权弹窗（如果系统支持），并打开系统设置中对应的页面。
    func request(_ permission: Permission)
}

/// 功能设置。每个功能最多一个设置类型，存储在 config/features/<featureID>.json。
/// 规则：字段只增不删（缺失的字段会自动用默认值补齐）；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
public protocol FeatureSettings: Codable, Sendable, Equatable {
    static var schemaVersion: Int { get }
    static var defaultValue: Self { get }
    /// 把旧版本的 JSON 迁移到当前版本。`version` 是文件中记录的版本号。
    static func migrate(_ json: inout JSONValue, from version: Int) throws
}

public extension FeatureSettings {
    static var schemaVersion: Int {
        1
    }

    static func migrate(_: inout JSONValue, from _: Int) throws {}
}

@MainActor
public protocol SettingsService: AnyObject {
    func load<S: FeatureSettings>(_ type: S.Type) -> S
    func save(_ value: some FeatureSettings)
    /// 设置变化流（包括来自设置界面的修改）。
    func changes<S: FeatureSettings>(_ type: S.Type) -> AsyncStream<S>
}

@MainActor
public protocol StorageService: AnyObject {
    /// 本功能私有的数据目录：~/Library/Application Support/MAIO/data/<featureID>/（首次访问时创建）。
    func dataDirectory() throws -> URL
}

@MainActor
public protocol OverlayService: AnyObject {
    /// 屏幕中央的短暂提示
    func showHUD(_ message: String, symbol: String?)
    func showError(_ message: String)
}

public extension OverlayService {
    func showHUD(_ message: String) {
        showHUD(message, symbol: nil)
    }
}

@MainActor
public protocol SystemEventService: AnyObject {
    var frontmostBundleID: String? { get }
    func frontmostApplicationChanges() -> AsyncStream<String?>
}

/// 密钥存储（ADR-0009）：API Key 等敏感信息只存在这里，不要写进设置文件。
/// 按功能隔离，键由功能自己决定。
@MainActor
public protocol SecretService: AnyObject {
    func secret(for key: String) -> String?
    /// 传 nil 或空字符串表示删除。
    func setSecret(_ value: String?, for key: String) throws
}

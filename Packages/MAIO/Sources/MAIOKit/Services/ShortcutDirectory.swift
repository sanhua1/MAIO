/// 一个组合键被谁占用（ADR-0018）。设置界面据此实时提示冲突。
public struct ShortcutOccupant: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// macOS 系统快捷键：系统先处理，MAIO 和其他 App 都收不到
        case system
        /// MAIO 的快捷键绑定（快捷键页）
        case binding
        /// 某个功能登记占用的按键（例如 Finder 增强在 Finder 里的改键）
        case feature(FeatureID)
    }

    public let kind: Kind
    /// 例如"聚焦搜索"、"剪贴板：显示面板"、"Finder 增强：剪切"
    public let title: String
    public let scope: BindingScope

    public init(kind: Kind, title: String, scope: BindingScope = .global) {
        self.kind = kind
        self.title = title
        self.scope = scope
    }

    public var id: String {
        "\(kind)|\(title)"
    }
}

/// 功能登记"我在这些 App 里占用了这些键"。
public struct ReservedShortcut: Sendable, Hashable {
    public let chord: KeyChord
    public let scope: BindingScope
    public let title: String

    public init(chord: KeyChord, scope: BindingScope, title: String) {
        self.chord = chord
        self.scope = scope
        self.title = title
    }
}

/// 查询组合键的占用情况，并登记本功能占用的键。按功能隔离：查询结果不包含本功能自己登记的键。
@MainActor
public protocol ShortcutDirectory: AnyObject {
    /// 在 `scope` 范围内，还有谁用了这个组合键（系统快捷键、MAIO 绑定、其他功能登记的键）
    func occupants(of chord: KeyChord, scope: BindingScope) -> [ShortcutOccupant]
    /// 替换本功能登记的全部按键；功能停用时宿主自动清空
    func reserve(_ shortcuts: [ReservedShortcut])
}

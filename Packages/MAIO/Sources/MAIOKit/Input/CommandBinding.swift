/// 触发器：产生"执行某命令"请求的来源。以后新增的触发方式（双击修饰键、鼠标侧键……）都加在这里。
public enum Trigger: Sendable, Hashable {
    case hotkey(KeyChord)

    public var displayString: String {
        switch self {
        case let .hotkey(chord): chord.displayString
        }
    }
}

extension Trigger: Codable {
    private enum CodingKeys: String, CodingKey { case hotkey }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try .hotkey(container.decode(KeyChord.self, forKey: .hotkey))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hotkey(chord): try container.encode(chord, forKey: .hotkey)
        }
    }
}

/// 绑定的生效范围（按前台 App 的 bundle ID 判断）。
public enum BindingScope: Sendable, Hashable {
    case global
    case onlyIn([String])
    case exceptIn([String])

    public func applies(to bundleID: String?) -> Bool {
        switch self {
        case .global: true
        case let .onlyIn(apps): bundleID.map(apps.contains) ?? false
        case let .exceptIn(apps): !(bundleID.map(apps.contains) ?? false)
        }
    }
}

extension BindingScope: Codable {
    private enum CodingKeys: String, CodingKey { case only, except }

    public init(from decoder: any Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self), raw == "global" {
            self = .global
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let apps = try container.decodeIfPresent([String].self, forKey: .only) {
            self = .onlyIn(apps)
        } else {
            self = try .exceptIn(container.decode([String].self, forKey: .except))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .global:
            var container = encoder.singleValueContainer()
            try container.encode("global")
        case let .onlyIn(apps):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(apps, forKey: .only)
        case let .exceptIn(apps):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(apps, forKey: .except)
        }
    }
}

/// 用户绑定：触发器 → 命令 + 参数。存储在 bindings.json 中。
public struct CommandBinding: Sendable, Hashable, Identifiable {
    public var id: String
    public var trigger: Trigger
    public var command: CommandID
    public var arguments: CommandArguments
    public var scope: BindingScope
    public var isEnabled: Bool
    /// 用户备注（可选）
    public var title: String?

    public init(
        id: String,
        trigger: Trigger,
        command: CommandID,
        arguments: CommandArguments = [:],
        scope: BindingScope = .global,
        isEnabled: Bool = true,
        title: String? = nil,
    ) {
        self.id = id
        self.trigger = trigger
        self.command = command
        self.arguments = arguments
        self.scope = scope
        self.isEnabled = isEnabled
        self.title = title
    }
}

extension CommandBinding: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, trigger, command, arguments, scope, title
        case isEnabled = "enabled"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        trigger = try container.decode(Trigger.self, forKey: .trigger)
        command = try container.decode(CommandID.self, forKey: .command)
        arguments = try container.decodeIfPresent(CommandArguments.self, forKey: .arguments) ?? [:]
        scope = try container.decodeIfPresent(BindingScope.self, forKey: .scope) ?? .global
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }
}

/// 功能在 manifest 中声明的出厂快捷键。`id` 必须稳定：用户删除后不会被重新添加。
public struct DefaultBinding: Sendable, Hashable {
    public let id: String
    public let trigger: Trigger
    public let command: CommandID
    public let arguments: CommandArguments

    public init(id: String, trigger: Trigger, command: CommandID, arguments: CommandArguments = [:]) {
        self.id = id
        self.trigger = trigger
        self.command = command
        self.arguments = arguments
    }

    public var binding: CommandBinding {
        CommandBinding(id: id, trigger: trigger, command: command, arguments: arguments)
    }
}

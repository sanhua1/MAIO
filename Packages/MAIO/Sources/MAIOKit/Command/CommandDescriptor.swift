/// 命令参数（键 → JSON 值）。
public typealias CommandArguments = [String: JSONValue]

/// 命令的静态描述：绑定编辑器据此展示命令名称、自动生成参数表单。
public struct CommandDescriptor: Sendable, Hashable, Identifiable {
    public let id: CommandID
    public let title: String
    public let summary: String?
    public let parameters: [ParameterSpec]

    public init(id: CommandID, title: String, summary: String? = nil, parameters: [ParameterSpec] = []) {
        self.id = id
        self.title = title
        self.summary = summary
        self.parameters = parameters
    }
}

/// 命令参数声明。
public struct ParameterSpec: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case text
        case multilineText
        case bool
        case number
        /// App 的 bundle ID 或 .app 路径
        case application
        /// 快捷键字符串，例如 "cmd+shift+4"
        case keyChord
        case choice([String])
    }

    public let key: String
    public let title: String
    public let kind: Kind
    public let isRequired: Bool
    public let placeholder: String?
    public let defaultValue: JSONValue?

    public var id: String {
        key
    }

    public init(
        key: String,
        title: String,
        kind: Kind,
        isRequired: Bool = true,
        placeholder: String? = nil,
        defaultValue: JSONValue? = nil,
    ) {
        self.key = key
        self.title = title
        self.kind = kind
        self.isRequired = isRequired
        self.placeholder = placeholder
        self.defaultValue = defaultValue
    }
}

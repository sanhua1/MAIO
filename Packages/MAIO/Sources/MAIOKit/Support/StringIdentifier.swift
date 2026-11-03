/// 以字符串为底的强类型标识符的公共行为。
public protocol StringIdentifier: RawRepresentable, Hashable, Sendable, Codable, Comparable,
    ExpressibleByStringLiteral, CustomStringConvertible where RawValue == String {
    init(rawValue: String)
}

public extension StringIdentifier {
    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    init(from decoder: any Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 功能 ID，例如 "clipboard"。全局唯一，一旦发布永不改名（它是配置文件名和命令前缀）。
public struct FeatureID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// 宿主自身（菜单栏、设置窗口）注册命令时使用的所有者。
    public static let core: FeatureID = "maio"
}

/// 命令 ID，格式固定为 "<featureID>.<verb>"，例如 "screenshot.captureRegion"。
public struct CommandID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// 命令所属功能（点号前的部分）。
    public var featureID: FeatureID {
        FeatureID(rawValue: String(rawValue.prefix { $0 != "." }))
    }
}

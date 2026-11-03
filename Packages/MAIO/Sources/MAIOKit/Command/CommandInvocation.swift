import Foundation

/// 命令是从哪里被触发的。
public enum CommandSource: Sendable, Hashable {
    /// 快捷键触发：chord 是实际触发的组合键（见 ADR-0007）
    case hotkey(bindingID: String, chord: KeyChord)
    case menu
    case url
    case feature(FeatureID)
    case test
}

/// 一次命令调用：参数 + 来源，并提供带校验的参数读取方法。
public struct CommandInvocation: Sendable {
    public let commandID: CommandID
    public let arguments: CommandArguments
    public let source: CommandSource

    public init(commandID: CommandID, arguments: CommandArguments, source: CommandSource) {
        self.commandID = commandID
        self.arguments = arguments
        self.source = source
    }

    public func string(_ key: String) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw CommandError.invalidArgument(key: key, reason: "缺少必填的文本参数")
        }
        return value
    }

    public func optionalString(_ key: String) -> String? {
        arguments[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func bool(_ key: String, default fallback: Bool) -> Bool {
        arguments[key]?.boolValue ?? fallback
    }

    public func number(_ key: String, default fallback: Double) -> Double {
        arguments[key]?.numberValue ?? fallback
    }
}

/// 命令执行错误。功能自己的业务错误可以包装成 `.failed`。
public enum CommandError: Error, Equatable, LocalizedError {
    /// 命令不存在，或提供它的功能未启用
    case unavailable(CommandID)
    case invalidArgument(key: String, reason: String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(id): "命令不可用：\(id)（对应功能可能未启用）"
        case let .invalidArgument(key, reason): "参数 \(key) 无效：\(reason)"
        case let .failed(message): message
        }
    }
}

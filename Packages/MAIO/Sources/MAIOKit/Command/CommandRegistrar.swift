/// 原始命令处理器：所有命令最终都以这种形式注册。返回值仅契约命令使用，普通命令返回 `.null`。
public typealias RawCommandHandler = @MainActor (CommandInvocation) async throws -> JSONValue

/// 普通命令处理器。
public typealias CommandHandler = @MainActor (CommandInvocation) async throws -> Void

/// 功能注册和调用命令的入口（通过 `FeatureContext.commands` 获得）。
/// 宿主在功能停用时会自动注销它注册的全部命令，功能不需要手动注销。
@MainActor
public protocol CommandRegistrar: AnyObject {
    /// 注册命令。命令 ID 必须以本功能 ID 为前缀。
    func register(_ descriptor: CommandDescriptor, rawHandler: @escaping RawCommandHandler)
    /// 调用任意命令（包括其他功能的命令）。目标不可用时抛出 `CommandError.unavailable`。
    @discardableResult
    func perform(_ id: CommandID, arguments: CommandArguments) async throws -> JSONValue
    func isAvailable(_ id: CommandID) -> Bool
    /// 当前能执行的全部命令（已启用的功能实际注册了的），按功能在目录里的顺序排列（ADR-0021）
    func availableCommands() -> [AvailableCommand]
}

public extension CommandRegistrar {
    func register(_ descriptor: CommandDescriptor, handler: @escaping CommandHandler) {
        register(descriptor) { invocation in
            try await handler(invocation)
            return .null
        }
    }

    @discardableResult
    func perform(_ id: CommandID) async throws -> JSONValue {
        try await perform(id, arguments: [:])
    }
}

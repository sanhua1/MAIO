/// 跨功能契约：提供方和调用方都只依赖契约，互不 import（见 ARCHITECTURE §4.3）。
/// 所有契约都定义在 `MAIOKit/Contracts/` 下。
public protocol CommandContract {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Codable & Sendable = NoOutput
    static var descriptor: CommandDescriptor { get }
}

public extension CommandContract {
    static var id: CommandID {
        descriptor.id
    }
}

/// 没有返回值的契约使用它作为 Output。
public struct NoOutput: Codable, Sendable, Equatable {
    public init() {}
    public init(from _: any Decoder) throws {}
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

public extension CommandRegistrar {
    /// 提供方：实现一个契约。契约命令同样可以被快捷键绑定（参数按 Input 的字段解码）。
    func register<C: CommandContract>(
        _: C.Type,
        handler: @escaping @MainActor (C.Input) async throws -> C.Output,
    ) {
        register(C.descriptor) { invocation in
            let input: C.Input
            do {
                input = try JSONValue.object(invocation.arguments).decode(C.Input.self)
            } catch {
                throw CommandError.invalidArgument(key: "*", reason: "参数与契约 \(C.id) 不匹配：\(error)")
            }
            return try await JSONValue(encoding: handler(input))
        }
    }

    /// 调用方：通过契约调用其他功能。
    func perform<C: CommandContract>(_: C.Type, _ input: C.Input) async throws -> C.Output {
        guard case let .object(arguments) = try JSONValue(encoding: input) else {
            throw CommandError.invalidArgument(key: "*", reason: "契约输入必须编码为 JSON 对象")
        }
        let output = try await perform(C.id, arguments: arguments)
        return try output.decode(C.Output.self)
    }
}

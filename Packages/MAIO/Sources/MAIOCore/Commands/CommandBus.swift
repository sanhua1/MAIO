import MAIOKit
import Observation
import os

/// 命令总线：保存所有已注册命令，负责分发调用。
@MainActor
@Observable
public final class CommandBus {
    struct Entry {
        let descriptor: CommandDescriptor
        let owner: FeatureID
        let handler: RawCommandHandler
    }

    private var entries: [CommandID: Entry] = [:]
    /// 功能目录（列出命令时用来排序、给出功能名）
    @ObservationIgnored private var manifests: [FeatureManifest] = []
    @ObservationIgnored private var changeHandlers: [() -> Void] = []
    @ObservationIgnored private let logger = Logger(subsystem: "app.maio", category: "commands")

    /// 命令执行失败时调用（宿主据此显示 HUD）。
    @ObservationIgnored public var onFailure: ((CommandID, any Error) -> Void)?

    public init() {}

    public var availableIDs: Set<CommandID> {
        Set(entries.keys)
    }

    public func isAvailable(_ id: CommandID) -> Bool {
        entries[id] != nil
    }

    /// 宿主启动时传入功能目录
    public func describeFeatures(_ manifests: [FeatureManifest]) {
        self.manifests = manifests
    }

    /// 已注册的命令：按功能在目录里的顺序，功能内按 manifest 声明的顺序，未声明的按 ID 排在最后（ADR-0021）
    public func availableCommands() -> [AvailableCommand] {
        var remaining = entries
        var result: [AvailableCommand] = []
        for manifest in manifests {
            let owned = remaining.values.filter { $0.owner == manifest.id }
            let order = Dictionary(manifest.commands.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            let sorted = owned.sorted { lhs, rhs in
                let left = order[lhs.descriptor.id] ?? Int.max
                let right = order[rhs.descriptor.id] ?? Int.max
                return left != right ? left < right : lhs.descriptor.id.rawValue < rhs.descriptor.id.rawValue
            }
            for entry in sorted {
                remaining[entry.descriptor.id] = nil
                result.append(AvailableCommand(
                    descriptor: entry.descriptor, featureID: manifest.id,
                    featureName: manifest.displayName, featureSymbol: manifest.symbol,
                ))
            }
        }
        let unknown = remaining.values.sorted { $0.descriptor.id.rawValue < $1.descriptor.id.rawValue }
        return result + unknown.map { entry in
            AvailableCommand(
                descriptor: entry.descriptor, featureID: entry.owner,
                featureName: entry.owner.rawValue, featureSymbol: "command",
            )
        }
    }

    public func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    /// 注册命令。命令 ID 必须以所有者的功能 ID 为前缀，且不能与其他功能冲突。
    @discardableResult
    public func register(_ descriptor: CommandDescriptor, owner: FeatureID, handler: @escaping RawCommandHandler) -> Bool {
        guard descriptor.id.featureID == owner else {
            logger.fault("命令 \(descriptor.id, privacy: .public) 不属于 \(owner, privacy: .public)，已拒绝注册")
            return false
        }
        if let existing = entries[descriptor.id], existing.owner != owner {
            logger.fault("命令 \(descriptor.id, privacy: .public) 已被 \(existing.owner, privacy: .public) 注册")
            return false
        }
        entries[descriptor.id] = Entry(descriptor: descriptor, owner: owner, handler: handler)
        notifyChange()
        return true
    }

    public func unregisterAll(owner: FeatureID) {
        let before = entries.count
        entries = entries.filter { $0.value.owner != owner }
        if entries.count != before {
            notifyChange()
        }
    }

    @discardableResult
    public func perform(_ id: CommandID, arguments: CommandArguments = [:], source: CommandSource) async throws -> JSONValue {
        guard let entry = entries[id] else { throw CommandError.unavailable(id) }
        logger.debug("perform \(id, privacy: .public)")
        return try await entry.handler(CommandInvocation(commandID: id, arguments: arguments, source: source))
    }

    /// 触发器（快捷键、菜单、URL）使用：错误不抛出，统一交给 onFailure 处理。
    public func fire(_ id: CommandID, arguments: CommandArguments, source: CommandSource) {
        logger.notice("fire \(id, privacy: .public) from \(String(describing: source), privacy: .public)")
        Task {
            do {
                try await perform(id, arguments: arguments, source: source)
            } catch {
                logger.error("命令 \(id, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)")
                onFailure?(id, error)
            }
        }
    }

    /// 给某个功能使用的注册器（自动带上所有者和调用来源）。
    func registrar(for owner: FeatureID) -> any CommandRegistrar {
        ScopedCommandRegistrar(bus: self, owner: owner)
    }

    private func notifyChange() {
        changeHandlers.forEach { $0() }
    }
}

@MainActor
private final class ScopedCommandRegistrar: CommandRegistrar {
    private let bus: CommandBus
    private let owner: FeatureID

    init(bus: CommandBus, owner: FeatureID) {
        self.bus = bus
        self.owner = owner
    }

    func register(_ descriptor: CommandDescriptor, rawHandler: @escaping RawCommandHandler) {
        bus.register(descriptor, owner: owner, handler: rawHandler)
    }

    func perform(_ id: CommandID, arguments: CommandArguments) async throws -> JSONValue {
        try await bus.perform(id, arguments: arguments, source: .feature(owner))
    }

    func isAvailable(_ id: CommandID) -> Bool {
        bus.isAvailable(id)
    }

    func availableCommands() -> [AvailableCommand] {
        bus.availableCommands()
    }
}

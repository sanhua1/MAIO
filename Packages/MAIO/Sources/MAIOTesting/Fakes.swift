import Foundation
import MAIOKit
import os
import Synchronization

/// 内存中的命令注册表，记录注册与调用。
@MainActor
public final class FakeCommandRegistrar: CommandRegistrar {
    public private(set) var descriptors: [CommandID: CommandDescriptor] = [:]
    public private(set) var performed: [(CommandID, CommandArguments)] = []
    private var handlers: [CommandID: RawCommandHandler] = [:]

    public init() {}

    public func register(_ descriptor: CommandDescriptor, rawHandler: @escaping RawCommandHandler) {
        descriptors[descriptor.id] = descriptor
        handlers[descriptor.id] = rawHandler
    }

    public func perform(_ id: CommandID, arguments: CommandArguments) async throws -> JSONValue {
        performed.append((id, arguments))
        guard let handler = handlers[id] else { throw CommandError.unavailable(id) }
        return try await handler(CommandInvocation(commandID: id, arguments: arguments, source: .test))
    }

    public func isAvailable(_ id: CommandID) -> Bool {
        handlers[id] != nil
    }

    /// 注册过的命令（按 ID 排序；功能名用功能 ID 代替）
    public func availableCommands() -> [AvailableCommand] {
        descriptors.values.sorted { $0.id.rawValue < $1.id.rawValue }.map { descriptor in
            AvailableCommand(
                descriptor: descriptor, featureID: descriptor.id.featureID,
                featureName: descriptor.id.featureID.rawValue, featureSymbol: "command",
            )
        }
    }
}

/// 记录所有合成事件。
public final class RecordingPoster: SyntheticEventPoster {
    private let storage = Mutex<[SyntheticEvent]>([])
    public init() {}
    public func post(_ event: SyntheticEvent) {
        storage.withLock { $0.append(event) }
    }

    public var events: [SyntheticEvent] {
        storage.withLock { $0 }
    }
}

public final class FakeKeyboardSession: KeyboardSession {
    public let events: AsyncStream<KeyEvent>
    public let continuation: AsyncStream<KeyEvent>.Continuation

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    public func end() {
        continuation.finish()
    }
}

@MainActor
public final class FakeInputService: InputService {
    public let recordingPoster = RecordingPoster()
    public private(set) var filters: [FilterToken: (any RealtimeInputFilter, FilterStage)] = [:]
    public private(set) var sessions: [FakeKeyboardSession] = []
    private var nextToken: UInt64 = 1

    public init() {}
    public var poster: any SyntheticEventPoster {
        recordingPoster
    }

    public func beginKeyboardSession() -> any KeyboardSession {
        let session = FakeKeyboardSession()
        sessions.append(session)
        return session
    }

    public func registerFilter(_ filter: any RealtimeInputFilter, for _: PointerEventKind, stage: FilterStage)
        -> FilterToken {
        let token = FilterToken(rawValue: nextToken)
        nextToken += 1
        filters[token] = (filter, stage)
        return token
    }

    public private(set) var keyFilters: [FilterToken: any RealtimeKeyFilter] = [:]

    public func registerKeyFilter(_ filter: any RealtimeKeyFilter) -> FilterToken {
        let token = FilterToken(rawValue: nextToken)
        nextToken += 1
        keyFilters[token] = filter
        return token
    }

    public func removeFilter(_ token: FilterToken) {
        filters[token] = nil
        keyFilters[token] = nil
    }
}

@MainActor
public final class InMemorySettingsService: SettingsService {
    private var values: [ObjectIdentifier: any Sendable] = [:]
    public init() {}

    public func load<S: FeatureSettings>(_: S.Type) -> S {
        values[ObjectIdentifier(S.self)] as? S ?? S.defaultValue
    }

    public func save<S: FeatureSettings>(_ value: S) {
        values[ObjectIdentifier(S.self)] = value
    }

    public func changes<S: FeatureSettings>(_: S.Type) -> AsyncStream<S> {
        AsyncStream { _ in }
    }
}

@MainActor
public final class TemporaryStorage: StorageService {
    public let root: URL
    public init() {
        root = FileManager.default.temporaryDirectory.appending(path: "maio-tests-\(UUID().uuidString)")
    }

    public func dataDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

@MainActor
public final class FakePermissions: PermissionService {
    public var granted: Set<Permission>
    public init(granted: Set<Permission> = Set(Permission.allCases)) {
        self.granted = granted
    }

    public func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }

    public func request(_: Permission) {}
}

@MainActor
public final class RecordingOverlay: OverlayService {
    public private(set) var messages: [String] = []
    public private(set) var errors: [String] = []
    public init() {}
    public func showHUD(_ message: String, symbol _: String?) {
        messages.append(message)
    }

    public func showError(_ message: String) {
        errors.append(message)
    }
}

@MainActor
public final class FakeSystemEvents: SystemEventService {
    public var frontmostBundleID: String?
    public init(frontmostBundleID: String? = nil) {
        self.frontmostBundleID = frontmostBundleID
    }

    public func frontmostApplicationChanges() -> AsyncStream<String?> {
        AsyncStream { _ in }
    }
}

/// 功能单测用的完整上下文。各个假实现都公开暴露，方便断言。
@MainActor
public final class FakeFeatureContext: FeatureContext {
    public let featureID: FeatureID
    public let fakeCommands = FakeCommandRegistrar()
    public let fakeInput = FakeInputService()
    public let fakeSettings = InMemorySettingsService()
    public let fakeStorage = TemporaryStorage()
    public let fakeSecrets = InMemorySecrets()
    public let fakePermissions = FakePermissions()
    public let fakeOverlay = RecordingOverlay()
    public let fakeEvents = FakeSystemEvents()
    public let fakeShortcuts = FakeShortcutDirectory()
    public let logger = Logger(subsystem: "app.maio.tests", category: "fake")

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public var commands: any CommandRegistrar {
        fakeCommands
    }

    public var shortcuts: any ShortcutDirectory {
        fakeShortcuts
    }

    public var input: any InputService {
        fakeInput
    }

    public var settings: any SettingsService {
        fakeSettings
    }

    public var storage: any StorageService {
        fakeStorage
    }

    public var secrets: any SecretService {
        fakeSecrets
    }

    public var permissions: any PermissionService {
        fakePermissions
    }

    public var overlay: any OverlayService {
        fakeOverlay
    }

    public var events: any SystemEventService {
        fakeEvents
    }
}

/// 内存中的密钥存储。
@MainActor
public final class InMemorySecrets: SecretService {
    public private(set) var values: [String: String] = [:]
    public init() {}

    public func secret(for key: String) -> String? {
        values[key]
    }

    public func setSecret(_ value: String?, for key: String) throws {
        values[key] = value.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// 快捷键目录的假实现：`occupied` 里预置占用，`reserved` 记录功能登记的键
@MainActor
public final class FakeShortcutDirectory: ShortcutDirectory {
    public var occupied: [KeyChord: [ShortcutOccupant]] = [:]
    public private(set) var reserved: [ReservedShortcut] = []

    public init() {}

    public func occupants(of chord: KeyChord, scope _: BindingScope) -> [ShortcutOccupant] {
        occupied[chord] ?? []
    }

    public func reserve(_ shortcuts: [ReservedShortcut]) {
        reserved = shortcuts
    }
}

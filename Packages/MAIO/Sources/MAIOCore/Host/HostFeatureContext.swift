import Foundation
import MAIOKit
import os

/// 宿主为每个功能创建的上下文。功能停用时调用 `tearDown()` 清理它注册的一切。
@MainActor
final class HostFeatureContext: FeatureContext {
    let featureID: FeatureID
    let commands: any CommandRegistrar
    let settings: any SettingsService
    let storage: any StorageService
    let secrets: any SecretService
    let permissions: any PermissionService
    let overlay: any OverlayService
    let events: any SystemEventService
    let logger: Logger
    private let shortcutDirectory: FeatureShortcutDirectory
    var shortcuts: any ShortcutDirectory {
        shortcutDirectory
    }

    private let scopedInput: ScopedInputService
    var input: any InputService {
        scopedInput
    }

    init(featureID: FeatureID, services: FeatureHost.Services) {
        self.featureID = featureID
        commands = services.commandBus.registrar(for: featureID)
        settings = FeatureSettingsStore(featureID: featureID, config: services.config)
        storage = FeatureStorage(featureID: featureID, root: services.config.root)
        secrets = KeychainSecretStore(service: "app.maio.\(featureID.rawValue)")
        permissions = services.permissions
        overlay = services.overlay
        events = services.events
        logger = Logger(subsystem: "app.maio", category: featureID.rawValue)
        scopedInput = ScopedInputService(engine: services.input)
        shortcutDirectory = FeatureShortcutDirectory(featureID: featureID, sources: services.shortcuts)
    }

    func tearDown() {
        scopedInput.tearDown()
        shortcutDirectory.tearDown()
    }
}

/// 记录功能注册的过滤器和会话，停用时统一清理。
@MainActor
final class ScopedInputService: InputService {
    private let engine: InputEngine
    private var tokens: Set<FilterToken> = []
    private var sessions: [any KeyboardSession] = []

    init(engine: InputEngine) {
        self.engine = engine
    }

    var poster: any SyntheticEventPoster {
        engine.poster
    }

    func beginKeyboardSession() -> any KeyboardSession {
        let session = engine.beginKeyboardSession()
        sessions.append(session)
        return session
    }

    func registerFilter(_ filter: any RealtimeInputFilter, for _: PointerEventKind, stage: FilterStage) -> FilterToken {
        let token = engine.addFilter(filter, stage: stage)
        tokens.insert(token)
        return token
    }

    func registerKeyFilter(_ filter: any RealtimeKeyFilter) -> FilterToken {
        let token = engine.addKeyFilter(filter)
        tokens.insert(token)
        return token
    }

    func removeFilter(_ token: FilterToken) {
        guard tokens.remove(token) != nil else { return }
        engine.removeFilter(token)
    }

    func tearDown() {
        tokens.forEach(engine.removeFilter)
        tokens.removeAll()
        sessions.forEach { $0.end() }
        sessions.removeAll()
    }
}

@MainActor
final class FeatureStorage: StorageService {
    private let directory: URL

    init(featureID: FeatureID, root: URL) {
        directory = root.appending(path: "data/\(featureID.rawValue)", directoryHint: .isDirectory)
    }

    func dataDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

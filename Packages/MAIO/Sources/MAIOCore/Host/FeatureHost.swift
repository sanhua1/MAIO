import MAIOKit
import Observation
import os

/// 功能宿主：管理功能的生命周期与故障隔离（见 ARCHITECTURE §7）。
@MainActor
@Observable
public final class FeatureHost {
    public enum State: Equatable, Sendable {
        case disabled
        case needsPermission(Set<Permission>)
        case starting
        case running
        case failed(String)
    }

    struct Services {
        let config: ConfigStore
        let commandBus: CommandBus
        let input: InputEngine
        let permissions: any PermissionService
        let overlay: any OverlayService
        let events: any SystemEventService
    }

    public let catalog: [any Feature.Type]
    public private(set) var states: [FeatureID: State] = [:]
    @ObservationIgnored private var instances: [FeatureID: (feature: any Feature, context: HostFeatureContext)] = [:]
    @ObservationIgnored private var appConfig: AppConfig
    @ObservationIgnored private let services: Services
    @ObservationIgnored private let logger = Logger(subsystem: "app.maio", category: "host")

    init(catalog: [any Feature.Type], services: Services) {
        self.catalog = Self.validated(catalog)
        self.services = services
        appConfig = services.config.load(AppConfig.self, from: AppConfig.path, default: AppConfig())
        for type in self.catalog {
            states[type.manifest.id] = .disabled
        }
    }

    /// 注意：不要写成 `catalog.map(\.manifest)`，对元类型静态属性用 key path 会让 Swift 6.3 编译器崩溃。
    public var manifests: [FeatureManifest] {
        catalog.map { $0.manifest }
    }

    public func state(of id: FeatureID) -> State {
        states[id] ?? .disabled
    }

    public func isEnabled(_ id: FeatureID) -> Bool {
        if let entry = appConfig.features[id.rawValue] {
            return entry.enabled
        }
        return catalog.first { $0.manifest.id == id }?.manifest.enabledByDefault ?? false
    }

    public func feature(_ id: FeatureID) -> (any Feature)? {
        instances[id]?.feature
    }

    /// 启动所有已启用的功能。单个功能失败不影响其他功能。
    func startAll() async {
        for type in catalog where isEnabled(type.manifest.id) {
            await activate(type)
        }
    }

    public func setEnabled(_ enabled: Bool, for id: FeatureID) async {
        appConfig.features[id.rawValue] = .init(enabled: enabled)
        services.config.save(appConfig, to: AppConfig.path)
        guard let type = catalog.first(where: { $0.manifest.id == id }) else { return }
        if enabled {
            await activate(type)
        } else {
            await deactivate(id)
            states[id] = .disabled
        }
    }

    /// 权限变化后重试处于 needsPermission 状态的功能。
    public func retryPendingPermissions() async {
        for type in catalog {
            if case .needsPermission = state(of: type.manifest.id) {
                await activate(type)
            }
        }
    }

    public func stopAll() async {
        for id in instances.keys {
            await deactivate(id)
        }
    }

    private func activate(_ type: any Feature.Type) async {
        let manifest = type.manifest
        guard instances[manifest.id] == nil else { return }
        let missing = manifest.requiredPermissions.filter { !services.permissions.isGranted($0) }
        guard missing.isEmpty else {
            states[manifest.id] = .needsPermission(missing)
            return
        }
        states[manifest.id] = .starting
        let context = HostFeatureContext(featureID: manifest.id, services: services)
        let feature = type.init(context: context)
        do {
            try await feature.activate()
            instances[manifest.id] = (feature, context)
            states[manifest.id] = .running
            logger.info("功能 \(manifest.id, privacy: .public) 已启动")
        } catch {
            await feature.deactivate()
            cleanUp(manifest.id, context: context)
            states[manifest.id] = .failed(error.localizedDescription)
            logger.error("功能 \(manifest.id, privacy: .public) 启动失败：\(error.localizedDescription, privacy: .public)")
            services.overlay.showError("\(manifest.displayName) 启动失败：\(error.localizedDescription)")
        }
    }

    private func deactivate(_ id: FeatureID) async {
        guard let instance = instances.removeValue(forKey: id) else { return }
        await instance.feature.deactivate()
        cleanUp(id, context: instance.context)
    }

    private func cleanUp(_ id: FeatureID, context: HostFeatureContext) {
        services.commandBus.unregisterAll(owner: id)
        context.tearDown()
    }

    /// 功能 ID 重复是编程错误：保留第一个，丢弃其余并记录。
    private static func validated(_ catalog: [any Feature.Type]) -> [any Feature.Type] {
        var seen: Set<FeatureID> = []
        return catalog.filter { type in
            let isNew = seen.insert(type.manifest.id).inserted
            if !isNew {
                Logger(subsystem: "app.maio", category: "host").fault("重复的功能 ID：\(type.manifest.id, privacy: .public)")
            }
            return isNew
        }
    }
}

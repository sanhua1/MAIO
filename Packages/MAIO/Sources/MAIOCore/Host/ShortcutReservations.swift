import MAIOKit
import Observation

/// 各功能登记占用的按键（ADR-0018）。快捷键页用它提示"在某 App 里会被某功能占用"。
@MainActor
@Observable
public final class ShortcutReservations {
    public private(set) var byFeature: [FeatureID: [ReservedShortcut]] = [:]

    public init() {}

    func set(_ shortcuts: [ReservedShortcut], for feature: FeatureID) {
        byFeature[feature] = shortcuts.isEmpty ? nil : shortcuts
    }

    /// 与这个组合键、作用范围重叠的登记（可排除某个功能自己）
    public func reservations(
        of chord: KeyChord, scope: BindingScope, excluding: FeatureID? = nil,
    ) -> [(feature: FeatureID, shortcut: ReservedShortcut)] {
        byFeature.sorted { $0.key.rawValue < $1.key.rawValue }.flatMap { feature, shortcuts in
            feature == excluding ? [] : shortcuts.filter { $0.chord == chord && $0.scope.mayOverlap(scope) }
                .map { (feature, $0) }
        }
    }
}

/// 给单个功能的快捷键目录：查询时汇总系统快捷键、MAIO 绑定、其他功能的登记。
@MainActor
final class FeatureShortcutDirectory: ShortcutDirectory {
    struct Sources {
        let bindings: BindingStore
        let systemShortcuts: SystemShortcutManager
        let reservations: ShortcutReservations
        /// 命令 ID → 显示名称
        let commandTitle: @MainActor (CommandID) -> String
    }

    private let featureID: FeatureID
    private let sources: Sources

    init(featureID: FeatureID, sources: Sources) {
        self.featureID = featureID
        self.sources = sources
    }

    func occupants(of chord: KeyChord, scope: BindingScope) -> [ShortcutOccupant] {
        let system = sources.systemShortcuts.conflicts(for: chord).map {
            ShortcutOccupant(kind: .system, title: $0.info.name)
        }
        let bindings = sources.bindings.bindings.filter { binding in
            binding.isEnabled && binding.trigger == .hotkey(chord) && binding.scope.mayOverlap(scope)
                && !binding.command.rawValue.hasPrefix(featureID.rawValue + ".")
        }.map { ShortcutOccupant(kind: .binding, title: $0.title ?? sources.commandTitle($0.command), scope: $0.scope) }
        let features = sources.reservations.reservations(of: chord, scope: scope, excluding: featureID).map {
            ShortcutOccupant(kind: .feature($0.feature), title: $0.shortcut.title, scope: $0.shortcut.scope)
        }
        return system + bindings + features
    }

    func reserve(_ shortcuts: [ReservedShortcut]) {
        sources.reservations.set(shortcuts, for: featureID)
    }

    func tearDown() {
        sources.reservations.set([], for: featureID)
    }
}

import Foundation
import MAIOKit
import Observation

/// 用户绑定（config/bindings.json）。
@MainActor
@Observable
public final class BindingStore {
    struct File: Codable {
        var schemaVersion = 1
        var bindings: [CommandBinding] = []
        /// 已经添加过的出厂绑定 ID：用户删除出厂绑定后不会被重新添加
        var seededDefaults: [String] = []
    }

    static let path = "config/bindings.json"

    public private(set) var bindings: [CommandBinding] = []
    @ObservationIgnored private var seeded: Set<String> = []
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored var onChange: (() -> Void)?

    init(config: ConfigStore) {
        self.config = config
        let file = config.load(File.self, from: Self.path, default: File())
        bindings = file.bindings
        seeded = Set(file.seededDefaults)
    }

    /// 添加尚未添加过的出厂绑定。
    func seed(_ defaults: [DefaultBinding]) {
        let fresh = defaults.filter { !seeded.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for item in fresh {
            seeded.insert(item.id)
            if !bindings.contains(where: { $0.id == item.id }) {
                bindings.append(item.binding)
            }
        }
        persist()
    }

    public func upsert(_ binding: CommandBinding) {
        if let index = bindings.firstIndex(where: { $0.id == binding.id }) {
            bindings[index] = binding
        } else {
            bindings.append(binding)
        }
        persist()
    }

    public func remove(id: String) {
        bindings.removeAll { $0.id == id }
        persist()
    }

    /// 与 `binding` 使用相同触发器、且同时启用的其他绑定。
    public func conflicts(with binding: CommandBinding) -> [CommandBinding] {
        guard binding.isEnabled else { return [] }
        return bindings.filter {
            $0.id != binding.id && $0.isEnabled && $0.trigger == binding.trigger
                && $0.scope.mayOverlap(binding.scope)
        }
    }

    public static func makeID() -> String {
        UUID().uuidString
    }

    private func persist() {
        config.save(File(bindings: bindings, seededDefaults: seeded.sorted()), to: Self.path)
        onChange?()
    }
}

extension BindingScope {
    func mayOverlap(_ other: BindingScope) -> Bool {
        switch (self, other) {
        case let (.onlyIn(lhs), .onlyIn(rhs)): !Set(lhs).isDisjoint(with: rhs)
        default: true
        }
    }
}

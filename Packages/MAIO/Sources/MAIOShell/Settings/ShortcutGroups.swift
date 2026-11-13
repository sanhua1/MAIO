import MAIOKit
import SwiftUI

/// 「MAIO 快捷键」页列表里的一组：标签（全部 / MAIO 功能 / …）之下再按功能分组，
/// 例如"剪贴板"一组、"翻译"一组，然后是"打开 App""其他动作"。
struct ShortcutGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let isFeature: Bool
    var bindings: [CommandBinding]

    /// 按功能目录的顺序排：各功能 → 没有对应功能的命令 → 打开 App → 其他动作。组内保持绑定原来的顺序。
    @MainActor
    static func make(_ bindings: [CommandBinding], catalog: [FeatureManifest]) -> [ShortcutGroup] {
        var groups: [String: ShortcutGroup] = [:]
        for binding in bindings {
            let presentation = BindingPresentation(binding: binding, catalog: catalog)
            let empty = group(for: presentation)
            groups[empty.id, default: empty].bindings.append(binding)
        }
        let order = catalog.map(\.id.rawValue) + [unknownID, ShortcutCategory.apps.rawValue, ShortcutCategory.actions.rawValue]
        return order.compactMap { groups[$0] }
    }

    private static let unknownID = "unknown"

    @MainActor
    private static func group(for presentation: BindingPresentation) -> ShortcutGroup {
        switch presentation.category {
        case .apps:
            return ShortcutGroup(
                id: ShortcutCategory.apps.rawValue,
                title: "打开 App",
                symbol: "app.dashed",
                isFeature: false,
                bindings: [],
            )
        case .actions:
            return ShortcutGroup(
                id: ShortcutCategory.actions.rawValue,
                title: "其他动作",
                symbol: "bolt",
                isFeature: false,
                bindings: [],
            )
        case .all, .features:
            guard let manifest = presentation.manifest else {
                return ShortcutGroup(id: unknownID, title: "未知命令", symbol: "questionmark", isFeature: false, bindings: [])
            }
            return ShortcutGroup(
                id: manifest.id.rawValue, title: manifest.displayName, symbol: manifest.symbol, isFeature: true, bindings: [],
            )
        }
    }
}

/// 分组标题：功能图标 + 名称 + 条数
struct ShortcutGroupHeader: View {
    let group: ShortcutGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.symbol)
                .foregroundStyle(group.isFeature ? Color.accentColor : .secondary)
            Text(group.title)
            Text("\(group.bindings.count)").foregroundStyle(.tertiary)
        }
        .font(.subheadline.weight(.semibold))
    }
}

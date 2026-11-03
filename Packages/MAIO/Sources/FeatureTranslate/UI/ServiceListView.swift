import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// 翻译源列表：启用开关、排序、展开编辑、添加和删除。结果卡片按这里的顺序排列。
struct ServiceListView: View {
    @SwiftUI.Binding var services: [ServiceConfig]
    let secrets: any SecretService
    let factory: ProviderFactory
    @State private var expanded: ServiceConfig.ID?

    var body: some View {
        LabeledContent {
            addMenu
        } label: {
            LabelWithInfo("翻译源（按顺序显示结果）", info: Self.info)
        }
        ForEach($services) { $service in
            ServiceRow(
                service: $service,
                isExpanded: expandedBinding(service.id),
                secrets: secrets,
                factory: factory,
                actions: rowActions(service.id),
            )
        }
    }

    static let info = """
    打开的翻译源会同时翻译，结果按列表顺序显示。
    免费源（Google、必应、腾讯交互翻译）使用网页接口，不需要 Key，但对方改版时可能失效。
    需要 Key 的源请点击右侧的“申请 Key”获取；Key 保存在系统钥匙串中，不会写进配置文件。
    """

    private var addMenu: some View {
        Menu("添加翻译源") {
            Menu("大模型（OpenAI 兼容）") {
                ForEach(LLMPreset.all) { preset in
                    Button(preset.name) { add(preset.makeConfig(id: Self.newID(), isEnabled: true)) }
                }
                Divider()
                Button("自定义…") {
                    add(ServiceConfig(id: Self.newID(), kind: .openAICompatible, name: "自定义大模型", isEnabled: true))
                }
            }
            Divider()
            ForEach(ProviderKind.allCases.filter { $0 != .openAICompatible }) { kind in
                Button(kind.spec.displayName) { add(.make(kind: kind, id: Self.newID())) }
                    .disabled(services.contains { $0.kind == kind })
            }
        }
        .fixedSize()
    }

    private func add(_ config: ServiceConfig) {
        services.append(config)
        expanded = config.id
    }

    private func rowActions(_ id: ServiceConfig.ID) -> ServiceRow.Actions {
        ServiceRow.Actions(
            moveUp: { move(id, by: -1) },
            moveDown: { move(id, by: 1) },
            remove: { remove(id) },
        )
    }

    private func move(_ id: ServiceConfig.ID, by offset: Int) {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard services.indices.contains(target) else { return }
        services.swapAt(index, target)
    }

    private func remove(_ id: ServiceConfig.ID) {
        guard let service = services.first(where: { $0.id == id }) else { return }
        for field in service.spec.fields where field.kind == .secret {
            try? secrets.setSecret(nil, for: service.secretKey(field.key))
        }
        services.removeAll { $0.id == id }
    }

    private func expandedBinding(_ id: ServiceConfig.ID) -> SwiftUI.Binding<Bool> {
        SwiftUI.Binding(get: { expanded == id }, set: { expanded = $0 ? id : nil })
    }

    static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }
}

/// 一个翻译源：标题行 + 展开后的配置表单。
private struct ServiceRow: View {
    struct Actions {
        let moveUp: () -> Void
        let moveDown: () -> Void
        let remove: () -> Void
    }

    @SwiftUI.Binding var service: ServiceConfig
    @SwiftUI.Binding var isExpanded: Bool
    let secrets: any SecretService
    let factory: ProviderFactory
    let actions: Actions

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ServiceEditorView(service: $service, secrets: secrets, factory: factory)
            HStack {
                Button("上移", systemImage: "arrow.up", action: actions.moveUp)
                Button("下移", systemImage: "arrow.down", action: actions.moveDown)
                Spacer()
                Button("删除这个翻译源", role: .destructive, action: actions.remove)
            }
            .controlSize(.small)
        } label: {
            HStack {
                Toggle("", isOn: $service.isEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                Image(systemName: service.spec.symbol).frame(width: 18)
                Text(service.name)
                CostBadge(cost: service.spec.cost)
            }
        }
    }
}

struct CostBadge: View {
    let cost: ProviderSpec.Cost

    var body: some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var title: String {
        switch cost {
        case .free: "免费"
        case .offline: "离线"
        case .freeQuota: "需 Key · 有免费额度"
        case .paid: "需 Key"
        }
    }

    private var color: Color {
        switch cost {
        case .free, .offline: .green
        case .freeQuota: .blue
        case .paid: .orange
        }
    }
}

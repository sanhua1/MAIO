import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// 右键菜单页：扩展开关、每一项的开关、新建文件的模板
struct FinderContextMenuPage: View {
    let context: any FeatureContext
    let enhancer: FinderEnhancer
    @State private var value: FinderSettings
    @State private var status: FinderExtension.Status?
    @State private var templates: [String] = []

    init(context: any FeatureContext, enhancer: FinderEnhancer) {
        self.context = context
        self.enhancer = enhancer
        _value = State(initialValue: context.settings.load(FinderSettings.self))
    }

    var body: some View {
        Group {
            statusRow
            Text("在 Finder 里右键文件、文件夹或空白处时显示。").font(.caption).foregroundStyle(.secondary)
            ForEach(ContextMenuAction.allCases, id: \.self) { action in
                Toggle(isOn: binding(action)) {
                    Label(action.title + placeText(action), systemImage: action.symbol)
                }
            }
            Text("新建模板").font(.headline).padding(.top, 6)
            LabeledContent {
                HStack {
                    Button("打开模板文件夹") { openTemplates() }
                    Button("刷新") { reloadTemplates() }
                }
            } label: {
                LabelWithInfo("「新建」子菜单", info: FinderHelp.templates)
            }
            ForEach(templates, id: \.self) { name in
                Text(FileTemplates.title(of: name)).foregroundStyle(.secondary)
            }
        }
        .task {
            await refreshStatus()
            reloadTemplates()
        }
        .onChange(of: value) { _, newValue in context.settings.save(newValue) }
    }

    @ViewBuilder private var statusRow: some View {
        switch status {
        case .enabled:
            LabeledContent("右键菜单扩展") {
                HStack {
                    StatusBadge("已启用", tone: .positive)
                    Button("停用") { setEnabled(false) }
                }
            }
        case .disabled:
            LabeledContent {
                Button("启用") { setEnabled(true) }
            } label: {
                Label("右键菜单扩展没有启用", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        case .missing:
            Label("系统还没发现 MAIO 的 Finder 扩展：把 MAIO 放进「应用程序」文件夹后重新打开 MAIO", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case nil:
            ProgressView().controlSize(.small)
        }
    }

    private func placeText(_ action: ContextMenuAction) -> String {
        switch action.places {
        case [.items]: "（右键文件）"
        case [.container]: "（右键空白处）"
        default: ""
        }
    }

    private func binding(_ action: ContextMenuAction) -> Binding<Bool> {
        Binding(
            get: { !value.hiddenContextMenuItems.contains(action.rawValue) },
            set: { shown in
                value.hiddenContextMenuItems.removeAll { $0 == action.rawValue }
                if !shown {
                    value.hiddenContextMenuItems.append(action.rawValue)
                }
            },
        )
    }

    private func setEnabled(_ enabled: Bool) {
        Task {
            await FinderExtension.setEnabled(enabled)
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        status = await FinderExtension.status()
    }

    private func reloadTemplates() {
        enhancer.writeContextMenuConfig()
        templates = enhancer.templates?.list() ?? []
    }

    private func openTemplates() {
        guard let templates = enhancer.templates else { return }
        templates.seedIfNeeded()
        NSWorkspace.shared.open(templates.directory)
    }
}

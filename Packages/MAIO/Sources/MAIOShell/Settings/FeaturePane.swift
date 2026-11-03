import MAIOCore
import MAIOKit
import MAIOUI
import SwiftUI

struct FeaturePane: View {
    let controller: MAIOAppController
    let featureID: FeatureID

    private var host: FeatureHost {
        controller.runtime.host
    }

    private var manifest: FeatureManifest? {
        host.manifests.first { $0.id == featureID }
    }

    var body: some View {
        if let manifest {
            Form {
                Section {
                    Toggle(isOn: enabledBinding) {
                        Text(manifest.displayName)
                        Text(manifest.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("状态") { stateBadge }
                }
                if !manifest.commands.isEmpty {
                    FeatureShortcutsSection(controller: controller, manifest: manifest)
                }
                if let settings = host.feature(featureID)?.makeSettingsView() {
                    Section("设置") { settings }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(manifest.displayName)
        }
    }

    private var enabledBinding: SwiftUI.Binding<Bool> {
        SwiftUI.Binding(
            get: { host.isEnabled(featureID) },
            set: { enabled in Task { await host.setEnabled(enabled, for: featureID) } },
        )
    }

    @ViewBuilder private var stateBadge: some View {
        switch host.state(of: featureID) {
        case .disabled: StatusBadge("已停用", tone: .neutral)
        case .starting: StatusBadge("启动中", tone: .neutral)
        case .running: StatusBadge("运行中", tone: .positive)
        case let .needsPermission(missing):
            HStack {
                StatusBadge("缺少权限：" + missing.map(\.displayName).sorted().joined(separator: "、"), tone: .warning)
                Button("前往授权") { controller.showSettings(pane: .permissions) }
            }
        case let .failed(message): StatusBadge("启动失败：\(message)", tone: .negative)
        }
    }
}

import AppKit
import MAIOCore
import MAIOUI
import SwiftUI

struct GeneralPane: View {
    let controller: MAIOAppController
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            PermissionsSection(controller: controller)
            Section("启动") {
                Toggle("登录时启动 MAIO", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("输入引擎") {
                LabeledContent("键盘") { engineBadge }
                LabeledContent("指针（滚轮）") {
                    StatusBadge(
                        controller.runtime.input.isPointerTapRunning ? "运行中" : "未使用",
                        tone: controller.runtime.input.isPointerTapRunning ? .positive : .neutral,
                    )
                }
            }
            Section("配置") {
                LabeledContent("配置目录") {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([controller.runtime.config.root])
                    }
                }
                Text(controller.runtime.config.root.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                ForEach(controller.runtime.config.issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            UpdateSection(updater: controller.updater)
        }
        .formStyle(.grouped)
        .navigationTitle("通用")
    }

    @ViewBuilder private var engineBadge: some View {
        switch controller.runtime.input.status {
        case .running: StatusBadge("运行中", tone: .positive)
        case .waitingForPermission: StatusBadge("等待辅助功能权限", tone: .warning)
        case .stopped: StatusBadge("已停止", tone: .negative)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = "设置失败：\(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

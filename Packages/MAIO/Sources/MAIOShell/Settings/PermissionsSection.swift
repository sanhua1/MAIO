import MAIOKit
import MAIOUI
import SwiftUI

/// 「通用」页里的权限区：每项权限的状态、用途和授权按钮。
struct PermissionsSection: View {
    let controller: MAIOAppController
    /// 系统不会通知权限变化，页面可见期间每秒刷新一次
    @State private var tick = 0

    var body: some View {
        Section {
            ForEach(Permission.allCases) { permission in
                row(permission)
            }
        } header: {
            Text("权限")
        } footer: {
            Text("授权后如果状态没有变化，请在系统设置中把 MAIO 关掉再打开，或重启 MAIO。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick += 1
                await controller.runtime.host.retryPendingPermissions()
            }
        }
    }

    private func row(_ permission: Permission) -> some View {
        _ = tick
        let granted = controller.runtime.permissions.isGranted(permission)
        return LabeledContent {
            if granted {
                StatusBadge("已授权", tone: .positive)
            } else {
                Button("授权…") { controller.runtime.permissions.request(permission) }
            }
        } label: {
            Text(permission.displayName)
            Text(usage(of: permission)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func usage(of permission: Permission) -> String {
        let users = controller.runtime.host.manifests
            .filter { $0.requiredPermissions.contains(permission) }
            .map(\.displayName)
        let base = permission == .accessibility ? ["全局快捷键", "滚轮处理"] : []
        let all = base + users
        return all.isEmpty ? "当前没有功能需要" : "用于：" + all.joined(separator: "、")
    }
}

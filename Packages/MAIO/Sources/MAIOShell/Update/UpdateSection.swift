import SwiftUI

/// 通用设置页的"更新"区：当前版本、自动检查开关、立即检查、状态。
struct UpdateSection: View {
    @Bindable var updater: Updater

    var body: some View {
        Section {
            LabeledContent("版本", value: updater.currentVersion?.description ?? "开发版")
            Toggle("自动检查更新", isOn: $updater.settings.automaticChecks)
            LabeledContent {
                Button(buttonTitle) {
                    Task { await updater.check(userInitiated: true) }
                }
                .disabled(isBusy)
            } label: {
                Text(statusText)
                if let lastCheck = updater.settings.lastCheck {
                    Text("上次检查：\(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("更新")
        } footer: {
            Text("每 24 小时检查一次 GitHub 上的新版本。新版本会在后台下载并校验签名，下载好后询问是否安装；安装后自动重启，设置、数据和系统授权都会保留。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    private var buttonTitle: String {
        if case .ready = updater.state {
            return "安装…"
        }
        return "检查更新"
    }

    private var statusText: String {
        switch updater.state {
        case .idle: "检查更新"
        case .checking: "正在检查…"
        case .upToDate: "已是最新版本"
        case let .downloading(version): "正在下载 \(version)…"
        case let .ready(prepared): "\(prepared.release.version) 已下载好"
        case .installing: "正在安装…"
        case let .failed(message): "上次检查失败：\(message)"
        }
    }
}

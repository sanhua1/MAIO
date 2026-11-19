import AppKit
import MAIOCore
import MAIOUI
import SwiftUI

/// 通用 › 远程桌面（ADR-0027）：远程桌面 App 在前台时，MAIO 的快捷键和改键让给远程电脑。
struct RemoteDesktopSection: View {
    let mode: RemoteDesktopMode

    var body: some View {
        Section {
            Toggle("远程桌面在前台时，把按键让给远程电脑", isOn: enabledBinding)
            if mode.settings.enabled {
                ForEach(mode.settings.bundleIDs, id: \.self) { bundleID in
                    AppRow(bundleID: bundleID) { mode.remove(bundleID) }
                }
                HStack {
                    AppPickerMenu { bundleID, _ in mode.add(bundleID) }
                    Spacer()
                    Button("恢复默认名单") { mode.restoreDefaults() }
                        .disabled(mode.settings.bundleIDs == RemoteDesktopSettings.defaultBundleIDs)
                }
            }
        } header: {
            HStack {
                Text("远程桌面")
                if mode.isActive {
                    StatusBadge("生效中", tone: .positive)
                }
            }
        } footer: {
            Text("名单里的 App 在前台时，MAIO 的快捷键、Super Caps 和其他改键、鼠标按键改键都不生效，按键原样交给远程软件转发。系统层的单键改键（键盘重映射、改成单个键的条目）仍然生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { mode.settings.enabled }, set: { mode.setEnabled($0) })
    }
}

private struct AppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack {
            AppIconView(bundleID: bundleID)
            Text(Self.name(of: bundleID))
            Text(bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("从名单中移除")
        }
    }

    private static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return "未安装" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

struct SwitcherSettingsView: View {
    let settings: any SettingsService
    let permissions: any PermissionService
    @State private var value: SwitcherSettings

    init(settings: any SettingsService, permissions: any PermissionService) {
        self.settings = settings
        self.permissions = permissions
        _value = State(initialValue: settings.load(SwitcherSettings.self))
    }

    var body: some View {
        Group {
            LabeledContent {
                Text("按住修饰键连按主键选择，松开切换").font(.caption).foregroundStyle(.secondary)
            } label: {
                LabelWithInfo("触发键的规则", info: SwitcherHelp.trigger)
            }
            LabeledContent {
                Text("⇥ / → 下一个 · ⇧⇥ / ← 上一个 · Esc 取消 · W 关窗 · M 最小化 · H 隐藏 · Q 退出")
                    .font(.caption).foregroundStyle(.secondary)
            } label: {
                LabelWithInfo("切换时可用的按键", info: SwitcherHelp.keys)
            }
            LabeledContent {
                HStack {
                    Slider(value: $value.showDelay, in: SwitcherSettings.showDelayRange).frame(width: 200)
                    Text("\(Int(value.showDelay * 1000)) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
            } label: {
                LabelWithInfo("面板显示延迟", info: SwitcherHelp.delay)
            }
            Toggle(isOn: $value.showThumbnails) {
                LabelWithInfo("显示窗口缩略图", info: SwitcherHelp.thumbnails)
            }
            if value.showThumbnails, !permissions.isGranted(.screenRecording) {
                HStack {
                    Label("需要“屏幕与系统录音”权限，目前显示 App 图标", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("授权…") { permissions.request(.screenRecording) }
                }
            }
            Toggle("显示最小化的窗口", isOn: $value.showMinimizedWindows)
            Toggle("显示已隐藏的 App", isOn: $value.showHiddenApps)
            Toggle("显示没有窗口的 App", isOn: $value.showAppsWithoutWindows)
            Toggle(isOn: $value.oneItemPerApp) {
                LabelWithInfo("每个 App 只显示一项", info: SwitcherHelp.onePerApp)
            }
            ExcludedAppsEditor(bundleIDs: $value.excludedBundleIDs)
            HStack {
                Spacer()
                Button("恢复默认设置") { value = .defaultValue }
            }
        }
        .onChange(of: value) { _, newValue in settings.save(newValue) }
    }
}

private struct ExcludedAppsEditor: View {
    @Binding var bundleIDs: [String]

    var body: some View {
        LabeledContent {
            Button("添加 App…", action: add)
        } label: {
            LabelWithInfo("不显示的 App", info: SwitcherHelp.excluded)
        }
        ForEach(bundleIDs, id: \.self) { bundleID in
            HStack {
                Text(bundleID).font(.callout.monospaced())
                Spacer()
                Button("移除", systemImage: "minus.circle") { bundleIDs.removeAll { $0 == bundleID } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for id in panel.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier }) where !bundleIDs.contains(id) {
            bundleIDs.append(id)
        }
    }
}

enum SwitcherHelp {
    static let trigger = """
    在上方「快捷键」里录制任意组合键，就能换成自己习惯的触发键：

    • ⌥⇥（默认，类似 Windows 的 Alt+Tab）
    • ⌘⇥（替换系统的 App 切换器）
    • ⌘`、⌃⇥ 等

    规则：按住组合键里的修饰键，每按一次主键切到下一个；松开修饰键就切换过去。
    ⇧ 版本（例如 ⌥⇧⇥）绑定到"窗口切换（反向）"。
    """

    static let keys = """
    面板打开（修饰键按住）时：
    • ⇥、→、触发主键：下一个
    • ⇧⇥、←：上一个
    • ↑、↓：在网格中上下移动
    • Return / 空格：立即切换
    • Esc：取消
    • W：关闭选中的窗口
    • M：最小化选中的窗口
    • H：隐藏选中的 App
    • Q：退出选中的 App
    鼠标悬停选中，点击直接切换。
    """

    static let delay = """
    按下触发键后，等这么久才显示面板。

    在这之前松手，会直接切换到上一个窗口，屏幕不会闪一下面板——适合"快速按一下，在两个窗口间来回切"。
    """

    static let thumbnails = """
    在面板里显示每个窗口的实时截图，更容易认出要找的窗口。

    需要"屏幕与系统录音"权限（只在面板显示时截取，不保存、不上传）。没有权限时显示 App 图标。
    """

    static let onePerApp = """
    打开后，每个 App 只显示一项（它最近使用的窗口），类似系统自带的 ⌘⇥。
    关闭时，同一个 App 的每个窗口单独显示。
    """

    static let excluded = """
    这些 App 的窗口不会出现在切换器里，例如常驻的音乐播放器、聊天工具。
    """
}

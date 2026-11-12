import AppKit
import MAIOKit
import MAIOUI
import SwiftUI

/// 截图设置：快捷键提示、识别与取色、保存位置。
struct ScreenshotSettingsView: View {
    let settings: any SettingsService
    let permissions: any PermissionService
    let history: ScreenshotHistoryStore?
    let openHistory: () -> Void
    @State private var value: ScreenshotSettings

    init(
        settings: any SettingsService, permissions: any PermissionService, history: ScreenshotHistoryStore?,
        openHistory: @escaping () -> Void,
    ) {
        self.settings = settings
        self.permissions = permissions
        self.history = history
        self.openHistory = openHistory
        _value = State(initialValue: settings.load(ScreenshotSettings.self))
    }

    var body: some View {
        Group {
            warnings
            LabeledContent {
                Text("拖动框选 · ⏎ 复制 · ⌘S 保存 · Esc 退出").font(.caption).foregroundStyle(.secondary)
            } label: {
                LabelWithInfo("截图时的按键", info: ScreenshotHelp.keys)
            }
            Toggle(isOn: $value.alwaysDetectControls) {
                LabelWithInfo("总是识别控件", info: ScreenshotHelp.controls)
            }
            Toggle("显示放大镜", isOn: $value.showMagnifier)
            Picker("颜色格式", selection: $value.colorFormat) {
                ForEach(ColorFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            saveRows
            pinRows
            RecordingSettingsRows(value: $value)
            historyRows
            HStack {
                Spacer()
                Button("恢复默认设置") { value = .defaultValue }
            }
        }
        .onChange(of: value) { _, newValue in settings.save(newValue) }
    }

    @ViewBuilder private var warnings: some View {
        if !permissions.isGranted(.screenRecording) {
            LabeledContent {
                Button("去授权") { permissions.request(.screenRecording) }
            } label: {
                Label("没有「屏幕与系统录音」权限，无法截图。授权后需要重新打开 MAIO", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        if !FunctionKeyState.usesStandardFunctionKeys() {
            Label(ScreenshotHelp.functionKeys, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var saveRows: some View {
        LabeledContent {
            HStack {
                Text(value.saveDirectory.isEmpty ? "~/Pictures/MAIO" : value.saveDirectory)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("选择…") { chooseDirectory() }
                if !value.saveDirectory.isEmpty {
                    Button("恢复默认") { value.saveDirectory = "" }
                }
            }
        } label: {
            LabelWithInfo("保存文件夹", info: ScreenshotHelp.folder)
        }
        Toggle("⌘S 时询问保存位置", isOn: $value.askSaveLocation)
        Toggle(isOn: $value.autoSave) {
            LabelWithInfo("复制截图时同时保存到文件夹", info: ScreenshotHelp.autoSave)
        }
    }

    @ViewBuilder private var pinRows: some View {
        Toggle(isOn: $value.pinShadow) {
            LabelWithInfo("贴图显示阴影", info: ScreenshotHelp.pinShadow)
        }
        Picker(selection: $value.pinZoomModifier) {
            ForEach(PinModifier.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            LabelWithInfo("贴图缩放：修饰键 + 滚轮 / - =", info: ScreenshotHelp.pinKeys)
        }
        Picker("贴图透明度：修饰键 + 滚轮 / - =", selection: $value.pinOpacityModifier) {
            ForEach(PinModifier.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if value.pinZoomModifier == value.pinOpacityModifier {
            Label("两个修饰键相同时，只能调整缩放", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var historyRows: some View {
        LabeledContent {
            Button("打开截图历史…", action: openHistory)
        } label: {
            LabelWithInfo("截图历史", info: ScreenshotHelp.history)
        }
        Picker("最多保留", selection: $value.historyLimit) {
            ForEach(HistoryLimit.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if let history {
            HistoryStorageView(store: history)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            value.saveDirectory = url.path
        }
    }
}

/// 设置项的 ⓘ 说明文字。
enum ScreenshotHelp {
    static let keys = """
    按下后先冻结整个屏幕，再在静止的画面上框选，所以打开的菜单、悬浮提示也能截进去。
    截图时：拖动框选；单击选中高亮的窗口；F1 直接截全屏；F2 打开截图历史；⌘A 选中全屏；方向键移动 1 像素，⇧方向键调整大小；\
    ⏎ 或双击复制；⌘S 保存；C 复制颜色；⇧ 切换颜色格式；Esc 或右键先取消选区，再退出。
    """
    static let controls = "关闭时，鼠标悬停高亮的是窗口，按住 ⌘ 才高亮按钮、输入框等控件。打开后一直识别控件。识别控件需要辅助功能权限。"
    static let functionKeys = "系统设置里没有打开「将 F1、F2 等键用作标准功能键」，F1 是亮度键，⌥F1 不会触发截图。可以打开这个选项，或者在上方「快捷键」里换一个组合键。"
    static let folder = "⌘S 保存截图的位置。文件名形如 MAIO 2026-11-03 14.05.33.png。"
    static let pinShadow = "贴图四周显示系统主题色的发光，和背景区分开。关掉后贴图就是一张纯粹的图，可以和背景融为一体。"
    static let pinKeys = """
    在贴图上按住修饰键滚动滚轮（或按修饰键 + - / =），每次缩放或调整透明度 5%。默认直接滚轮（或 - =）缩放，⌘ + 滚轮（或 ⌘- ⌘=）调透明度。
    缩放以鼠标为中心；触控板双指捏合也可以缩放。数字键 1～9、0 直接把透明度设为 10%～90%、100%。
    如果系统「辅助功能 → 缩放」里打开了"使用修饰键滚动来缩放"，那个修饰键会先被系统用掉，请换一个。
    """
    static let history = """
    每次截图、贴图都会保存到截图历史（包括可以重新编辑的标注），在历史里可以重新贴图、复制、编辑、删除。
    超过上限时自动删除最旧的；收藏的不会被删除。
    """
    static let autoSave = "默认只复制并写入截图历史。打开后每次复制截图也会在保存文件夹里存一份 PNG。"
}

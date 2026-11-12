import MAIOKit
import MAIOUI
import SwiftUI

/// 剪贴板设置：弹出与粘贴、记录哪些内容、存储上限与清理。
struct ClipboardSettingsView: View {
    let settings: any SettingsService
    let store: ClipStore?
    @State private var value: ClipboardSettings

    init(settings: any SettingsService, store: ClipStore?) {
        self.settings = settings
        self.store = store
        _value = State(initialValue: settings.load(ClipboardSettings.self))
    }

    var body: some View {
        Group {
            LabeledContent {
                Text("⏎ 粘贴 · ⇧⏎ 纯文本 · ⌘1–9 快速粘贴 · ␣ 预览 · ⌘P 固定 · ⌘⌫ 删除 · 直接打字搜索")
                    .font(.caption).foregroundStyle(.secondary)
            } label: {
                Text("面板里的按键")
            }
            Picker(selection: $value.popupPosition) {
                ForEach(ClipboardSettings.PopupPosition.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                LabelWithInfo("弹出位置", info: ClipboardHelp.position)
            }
            Picker(selection: $value.searchMode) {
                ForEach(ClipboardSettings.SearchMode.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                LabelWithInfo("搜索方式", info: ClipboardHelp.searchMode)
            }
            if value.popupPosition == .caret {
                Picker("没有文字光标时", selection: $value.caretFallback) {
                    ForEach(ClipboardSettings.CaretFallback.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Toggle(isOn: $value.pasteDirectly) {
                LabelWithInfo("选中后直接粘贴", info: ClipboardHelp.pasteDirectly)
            }
            Toggle(isOn: $value.moveToTopOnPaste) {
                LabelWithInfo("粘贴过的条目移到最前", info: ClipboardHelp.moveToTop)
            }
            Toggle("记录富文本格式（RTF、HTML）", isOn: $value.recordRichText)
            Toggle("记录图片", isOn: $value.recordImages)
            Toggle(isOn: $value.recordFiles) {
                LabelWithInfo("记录复制的文件", info: ClipboardHelp.files)
            }
            Toggle(isOn: $value.searchImageText) {
                LabelWithInfo("搜索图片里的文字", info: ClipboardHelp.imageText)
            }
            Picker(selection: $value.storageLimit) {
                ForEach(StorageLimit.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                LabelWithInfo("存储上限", info: ClipboardHelp.limit)
            }
            if let store {
                StorageManagementView(store: store)
            }
            HStack {
                Spacer()
                Button("恢复默认设置") { value = .defaultValue }
            }
        }
        .onChange(of: value) { _, newValue in settings.save(newValue) }
    }
}

enum ClipboardHelp {
    static let searchMode = """
    按 ⌘F 或点搜索框才搜索（默认）：打开面板后方向键选择、⏎ 粘贴；按 ⌘F 开始搜索，搜完按 ⏎ 结束搜索，再按 ⏎ 粘贴。用输入法打中文时，确认拼音的那一下 ⏎ 不会误粘贴。

    直接打字搜索：打开面板直接打字就是搜索，⏎ 立即粘贴。
    """
    static let position = "文字光标处：在正在输入的位置下方弹出（和 Ditto 的 At Caret 一样）。当前不在输入框里、或者 App 不提供光标位置时，按下面的\"没有文字光标时\"放到屏幕中央或鼠标处。"
    static let pasteDirectly = "打开：回车后自动切回原来的 App 并粘贴。关闭：只把内容放到剪贴板，需要自己按 ⌘V。"
    static let moveToTop = "打开后，粘贴过的条目会排到第一条，下次按 ⌃V 默认选中它。关闭则按复制时间排序。"
    static let files = "只记录文件路径，不复制文件本身，不占空间。原文件被删除或移动后就无法粘贴了。"
    static let imageText = """
    打开后，复制的图片（包括复制的图片文件）会在后台用系统自带的文字识别（离线）识别一次，搜索时也能搜到图片里的字，命中的那段显示在缩略图旁边。

    以前的图片也会在后台慢慢补上（原图片文件已经被删的补不了）。关闭后不再识别，搜索也不搜图片里的字。
    """
    static let limit = "所有历史（不含固定的条目）超过上限时，自动删除最久没用过的。选“永久保留”则不自动删除，可以在下方手动清理。"
}

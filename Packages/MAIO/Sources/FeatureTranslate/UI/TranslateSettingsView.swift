import MAIOKit
import MAIOUI
import SwiftUI

/// 翻译设置：常规选项、翻译源列表、历史记录入口。
struct TranslateSettingsView: View {
    let settings: any SettingsService
    let secrets: any SecretService
    let factory: ProviderFactory
    let history: HistoryStore
    @State private var value: TranslateSettings
    @State private var showsHistory = false

    init(settings: any SettingsService, secrets: any SecretService, factory: ProviderFactory, history: HistoryStore) {
        self.settings = settings
        self.secrets = secrets
        self.factory = factory
        self.history = history
        _value = State(initialValue: settings.load(TranslateSettings.self))
    }

    var body: some View {
        Group {
            general
            ServiceListView(services: $value.services, secrets: secrets, factory: factory)
            historyRows
            HStack {
                Spacer()
                Button("恢复默认设置（保留翻译源和 Key）") {
                    let services = value.services
                    value = .defaultValue
                    value.services = services
                }
            }
        }
        .onChange(of: value) { _, newValue in settings.save(newValue) }
        .sheet(isPresented: $showsHistory) { HistoryView(store: history) }
    }

    @ViewBuilder private var general: some View {
        Picker(selection: $value.hotkeyBehavior) {
            ForEach(TranslateSettings.HotkeyBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            LabelWithInfo("按下快捷键时", info: TranslateHelp.behavior)
        }
        Picker(selection: $value.targetLanguage) {
            ForEach(Language.targets) { Text($0.displayName).tag($0) }
        } label: {
            LabelWithInfo("目标语言", info: TranslateHelp.target)
        }
        Picker(selection: $value.secondTargetLanguage) {
            ForEach(Language.targets) { Text($0.displayName).tag($0) }
        } label: {
            LabelWithInfo("原文已是目标语言时翻译成", info: TranslateHelp.secondTarget)
        }
        Toggle(isOn: $value.removeLineBreaks) {
            LabelWithInfo("自动删除换行", info: TranslateHelp.lineBreaks)
        }
        Picker("窗口位置", selection: $value.windowPosition) {
            ForEach(TranslateSettings.WindowPosition.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Picker(selection: $value.selectionWindowPosition) {
            ForEach(TranslateSettings.SelectionPosition.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            LabelWithInfo("翻译选中文字时的窗口位置", info: TranslateHelp.selectionPosition)
        }
        Toggle(isOn: $value.closeOnBlur) {
            LabelWithInfo("失去焦点时关闭窗口", info: TranslateHelp.closeOnBlur)
        }
        LabeledContent("字体大小") {
            HStack {
                Slider(value: $value.fontSize, in: TranslateSettings.fontSizeRange, step: 1).frame(width: 200)
                Text("\(Int(value.fontSize)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private var historyRows: some View {
        Toggle("记录翻译历史", isOn: $value.historyEnabled)
        if value.historyEnabled {
            Picker("最多保留", selection: $value.historyLimit) {
                ForEach(TranslateSettings.historyLimits, id: \.self) { Text("\($0) 条").tag($0) }
            }
        }
        LabeledContent("翻译历史") {
            Button("查看历史记录…") { showsHistory = true }
        }
    }
}

/// 设置项的 ⓘ 说明文字。
enum TranslateHelp {
    static let selectionPosition = "所选文字旁边：放在选中文字的下方，下方放不下时放上方。有些 App（例如部分浏览器、Electron 应用）不提供选中文字的位置，这时放在鼠标处。上面的\"窗口位置\"只管直接打开输入框的情况。"
    static let behavior = """
    有选中文字就翻译，否则打开输入框：最常用，一个快捷键搞定两种场景。
    只翻译选中的文字：没有选中文字时只提示，不打开窗口。
    读取选中文字时优先使用辅助功能接口；读不到时（例如 Chrome、Electron 应用）会模拟一次 ⌘C，读完立即恢复剪贴板原来的内容。
    """
    static let target = "原文会被翻译成这个语言。窗口里的语言栏可以临时改成其他语言。"
    static let secondTarget = "例如目标语言是中文时，选中中文会自动翻译成英文。原文语言由系统在本机识别，不联网。"
    static let lineBreaks = "从 PDF、网页复制的文字常在句子中间断行，翻译质量会变差。打开后会把断开的行拼回完整段落，保留空行分隔的段落。窗口里也有手动删除换行的按钮。"
    static let closeOnBlur = "点击其他地方时自动关闭翻译窗口。点窗口右上角的📌可以临时固定。"
}

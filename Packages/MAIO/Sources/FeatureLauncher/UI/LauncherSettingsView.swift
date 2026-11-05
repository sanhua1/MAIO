import MAIOKit
import MAIOUI
import SwiftUI

/// 启动器设置：面板行为、文件搜索、网页搜索引擎。
struct LauncherSettingsView: View {
    let settings: any SettingsService
    /// 文件索引的状态（功能没启用时是 nil）
    let status: FileIndexStatus?
    @State private var value: LauncherSettings

    init(settings: any SettingsService, status: FileIndexStatus?) {
        self.settings = settings
        self.status = status
        _value = State(initialValue: settings.load(LauncherSettings.self))
    }

    var body: some View {
        Group {
            Section("面板") {
                LabeledContent("面板里的按键") {
                    Text("⏎ 打开 · ⌘⏎ 在 Finder 中显示 · ⌘C 复制路径 · ⌘⇧C 复制文件 · ⌘1–9 快速打开 · ⇥ 切换来源 · Esc 清空 / 关闭")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("前缀") {
                    Text("a 空格：只搜应用 · f 空格：只搜文件 · d 空格：只搜文件夹 · 搜索引擎关键词 + 空格：网页搜索")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("关闭后再打开", selection: $value.keepQuerySeconds) {
                    Text("清空输入").tag(0.0)
                    Text("5 秒内保留输入").tag(5.0)
                    Text("30 秒内保留输入").tag(30.0)
                }
                Stepper("“全部”里最多显示 \(value.maxAppsInAll) 个应用", value: $value.maxAppsInAll, in: 1 ... 20)
                Toggle("输入为空时显示最近使用", isOn: $value.showRecents)
            }
            FileSearchSection(value: $value, status: status)
            Section("网页搜索") {
                Toggle("“全部”的最后一项是网页搜索", isOn: $value.showWebFallback)
                Picker("默认引擎", selection: $value.defaultEngine) {
                    ForEach(value.engines) { Text($0.name).tag($0.keyword) }
                }
                // 按位置而不是关键词区分行：改关键词时输入框不会失去焦点
                ForEach(value.engines.indices, id: \.self) { index in
                    EngineRow(engine: engineBinding(index)) { remove(at: index) }
                }
                Button("添加搜索引擎") { addEngine() }
                Text("URL 里的 {query} 会换成输入的内容。关键词不能重复，也不要用 a。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: value) { _, newValue in settings.save(newValue) }
    }

    /// 删除一行后，SwiftUI 可能还会用旧的位置读一次，越界时给个空值，不崩溃
    private func engineBinding(_ index: Int) -> Binding<WebSearchEngine> {
        Binding(
            get: { value.engines.indices.contains(index) ? value.engines[index] : WebSearchEngine(
                name: "",
                keyword: "",
                template: "",
            ) },
            set: { newValue in
                if value.engines.indices.contains(index) {
                    value.engines[index] = newValue
                }
            },
        )
    }

    private func remove(at index: Int) {
        guard value.engines.indices.contains(index) else { return }
        value.engines.remove(at: index)
        if !value.engines.contains(where: { $0.keyword == value.defaultEngine }) {
            value.defaultEngine = value.engines.first?.keyword ?? ""
        }
    }

    private func addEngine() {
        var index = 1
        while value.engines.contains(where: { $0.keyword == "s\(index)" }) {
            index += 1
        }
        value.engines.append(WebSearchEngine(name: "新引擎", keyword: "s\(index)", template: "https://example.com/?q={query}"))
    }
}

private struct EngineRow: View {
    @Binding var engine: WebSearchEngine
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("名称", text: $engine.name).frame(width: 90)
            TextField("关键词", text: $engine.keyword).frame(width: 60)
            TextField("URL", text: $engine.template)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
    }
}

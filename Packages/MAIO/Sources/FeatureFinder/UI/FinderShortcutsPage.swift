import MAIOKit
import MAIOUI
import SwiftUI

/// 快捷键页：MAIO 增强的动作表、速查面板、Finder 原生快捷键（展示和重设）。冲突实时提示。
struct FinderShortcutsPage: View {
    let context: any FeatureContext
    let enhancer: FinderEnhancer
    @Binding var restart: RestartState
    @State private var value: FinderSettings

    init(context: any FeatureContext, enhancer: FinderEnhancer, restart: Binding<RestartState>) {
        self.context = context
        self.enhancer = enhancer
        _restart = restart
        _value = State(initialValue: context.settings.load(FinderSettings.self))
    }

    var body: some View {
        Group {
            Text("只在 Finder 位于前台时生效；重命名、搜索框等正在输入文字时按键保持原样。")
                .font(.caption).foregroundStyle(.secondary)
            header("MAIO 增强")
            ForEach(FinderActionID.allCases, id: \.self) { action in
                actionRow(action)
            }
            extraRows
            header("速查面板")
            Toggle(isOn: $value.cheatSheetEnabled) { LabelWithInfo("长按 ⌘ 显示快捷键", info: FinderHelp.cheatSheet) }
            if value.cheatSheetEnabled {
                LabeledContent("按住多久") {
                    HStack {
                        Slider(value: $value.cheatSheetDelay, in: FinderSettings.cheatSheetDelayRange, step: 0.1)
                        Text(String(format: "%.1f 秒", value.cheatSheetDelay)).monospacedDigit().frame(width: 52)
                    }
                }
            }
            HStack {
                Spacer()
                Button("MAIO 增强恢复默认") { value = .defaultValue }
            }
            FinderNativeShortcuts(context: context, menu: enhancer.menu, settings: value, restart: $restart) {
                Task { await enhancer.refreshMenu() }
            }
        }
        .onChange(of: value) { _, newValue in context.settings.save(newValue) }
    }

    // MARK: 动作表

    private func actionRow(_ action: FinderActionID) -> some View {
        let setting = value.setting(for: action)
        let chord = setting.chord ?? action.info.defaultChord
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: enabledBinding(action)) {
                    LabelWithInfo(action.info.title, info: action.info.help)
                }
                .disabled(chord == nil)
                Spacer()
                if setting.chord != nil {
                    Button("默认") { value.update(action) { $0.chord = nil } }
                        .buttonStyle(.borderless).font(.caption)
                }
                ShortcutRecorder(chord: chord, input: context.input) { newChord in
                    value.update(action) {
                        $0.chord = newChord == action.info.defaultChord ? nil : newChord
                        $0.isEnabled = true
                    }
                }
                .disabled(!setting.isEnabled && chord != nil)
            }
            if setting.isEnabled, let chord {
                WarningList(warnings: FinderConflicts.forAction(
                    action, chord: chord, settings: value, menu: enhancer.menu.effectiveItems, external: external(chord),
                ))
            }
        }
    }

    /// 没有快捷键（默认不设、也没录过）时开关显示为关
    private func enabledBinding(_ action: FinderActionID) -> Binding<Bool> {
        Binding(
            get: { value.chord(for: action) != nil },
            set: { enabled in value.update(action) { $0.isEnabled = enabled } },
        )
    }

    @ViewBuilder private var extraRows: some View {
        if value.chord(for: .newTextFile) != nil {
            TextField("新建文件的名字", text: $value.newFileName)
        }
        if value.chord(for: .openTerminal) != nil {
            Picker("终端", selection: terminalSelection) {
                ForEach(TerminalApp.choices(selected: value.terminalBundleID)) { Text($0.name).tag($0.bundleID) }
                Divider()
                Text("选择其他 App…").tag(Self.chooseOtherTag)
            }
        }
    }

    private static let chooseOtherTag = "maio.chooseOtherTerminal"

    /// 选"选择其他 App…"时弹出选择面板；取消就保持原来的终端
    private var terminalSelection: Binding<String> {
        Binding(
            get: { value.terminalBundleID },
            set: { choice in
                if choice == Self.chooseOtherTag {
                    // 等选择器的菜单关掉、这次界面更新结束后再弹面板
                    Task { @MainActor in
                        if let bundleID = TerminalApp.chooseOther() {
                            value.terminalBundleID = bundleID
                        }
                    }
                } else {
                    value.terminalBundleID = choice
                }
            },
        )
    }

    private func external(_ chord: KeyChord) -> [ShortcutOccupant] {
        context.shortcuts.occupants(of: chord, scope: .onlyIn([FinderKeymap.bundleID]))
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.headline).padding(.top, 6)
    }
}

/// Finder 菜单里的原生快捷键：按菜单分组，可以搜索、重设、恢复默认
struct FinderNativeShortcuts: View {
    let context: any FeatureContext
    let menu: FinderMenuStore
    let settings: FinderSettings
    @Binding var restart: RestartState
    let refresh: () -> Void
    @State private var query = ""

    var body: some View {
        HStack {
            LabelWithInfo("Finder 原生快捷键", info: FinderHelp.native).font(.headline)
            Spacer()
            if menu.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button("重新读取", action: refresh).buttonStyle(.borderless)
        }
        .padding(.top, 6)
        if menu.items.isEmpty {
            Text("还没读到 Finder 的菜单（Finder 没在运行，或缺少辅助功能权限）。").foregroundStyle(.secondary)
        } else {
            // 表单里 TextField 的标题会变成左侧标签，输入框要单独给提示文字
            LabeledContent("搜索") {
                TextField("", text: $query, prompt: Text("菜单项或快捷键")).labelsHidden()
            }
            ForEach(groups, id: \.title) { group in
                DisclosureGroup("\(group.title)（\(group.items.count)）", isExpanded: expanded(group.title)) {
                    ForEach(group.items) { item in row(item) }
                }
            }
        }
    }

    @State private var expandedMenus: Set<String> = []

    private func expanded(_ title: String) -> Binding<Bool> {
        Binding(
            get: { !query.isEmpty || expandedMenus.contains(title) },
            set: { open in
                if open {
                    expandedMenus.insert(title)
                } else {
                    expandedMenus.remove(title)
                }
            },
        )
    }

    private var groups: [(title: String, items: [FinderMenuItem])] {
        let filtered = menu.items.filter { item in
            query.isEmpty || item.path.joined().localizedCaseInsensitiveContains(query)
                || currentChord(item)?.displayString.contains(query) == true
        }
        var order: [String] = []
        var grouped: [String: [FinderMenuItem]] = [:]
        for item in filtered {
            if grouped[item.menu] == nil {
                order.append(item.menu)
            }
            grouped[item.menu, default: []].append(item)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private func currentChord(_ item: FinderMenuItem) -> KeyChord? {
        menu.override(for: item.path) ?? item.chord
    }

    private func row(_ item: FinderMenuItem) -> some View {
        let chord = currentChord(item)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.path.dropFirst().joined(separator: " › "))
                Spacer()
                if menu.override(for: item.path) != nil {
                    StatusBadge("已改", tone: .neutral)
                    Button("恢复") { set(nil, for: item) }.buttonStyle(.borderless).font(.caption)
                }
                if item.isGlobe {
                    Text(item.displayChord).foregroundStyle(.secondary).help("🌐 快捷键由系统处理，不能在这里改")
                } else {
                    ShortcutRecorder(chord: chord, input: context.input) { set($0, for: item) }
                }
            }
            if let chord, !item.isGlobe {
                WarningList(warnings: FinderConflicts.forMenuItem(
                    item, chord: chord, settings: settings, menu: menu.effectiveItems,
                    external: context.shortcuts.occupants(of: chord, scope: .onlyIn([FinderKeymap.bundleID])),
                ))
            }
        }
    }

    private func set(_ chord: KeyChord?, for item: FinderMenuItem) {
        FinderBackups(storage: context.storage)?.rememberMenuShortcut(item.path)
        menu.setShortcut(chord, for: item.path)
        restart.needed = true
    }
}

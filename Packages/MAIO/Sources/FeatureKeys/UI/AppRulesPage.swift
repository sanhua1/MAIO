import AppKit
import MAIOKit
import SwiftUI

/// 按 App 改键（ADR-0026）：指定的 App 在前台时，修饰键 A 当作 B。
struct AppRulesPage: View {
    let context: any FeatureContext
    /// 功能没在运行时为 nil
    let controller: AppModifierController?
    @State private var value: KeysSettings

    init(context: any FeatureContext, controller: AppModifierController?) {
        self.context = context
        self.controller = controller
        _value = State(initialValue: context.settings.load(KeysSettings.self))
    }

    var body: some View {
        Group {
            PageIntro(
                symbol: "gamecontroller",
                title: "按 App 改键",
                text: "在指定的 App 里调换修饰键，切到别的 App 立即恢复。例如游戏里把 ⌘ 和 ⌃ 对调，保留 Windows 上 Ctrl + 技能的习惯。",
            )
            ForEach(value.appModifierRules.indices, id: \.self) { index in
                AppRuleSection(
                    rule: ruleBinding(index),
                    isActive: controller?.activeBundleID == value.appModifierRules[safe: index]?.bundleID,
                ) {
                    if value.appModifierRules.indices.contains(index) {
                        value.appModifierRules.remove(at: index)
                    }
                }
            }
            Section {
                AddAppMenu { bundleID, name in
                    value.appModifierRules.append(
                        AppModifierRule(bundleID: bundleID, name: name, swaps: ModifierSwap.commandControl),
                    )
                }
            } footer: {
                NoteLines(
                    "「⌘」「⌃」指你在「键盘重映射」里设置之后的键：最左边的键被设成了 ⌘，规则 ⌘ → ⌃ 就让它在这个 App 里变成 ⌃。",
                    "对所有键盘生效，在系统底层替换，游戏也能识别。",
                    "切换 App 时如果正按着修饰键，会等松开后再切换。",
                    "游戏的进程往往不是启动器本身：英雄联盟要选游戏运行时出现的「League of Legends」（com.riotgames.LeagueofLegends.GameClient），可以在对局中从运行中的 App 里选。",
                )
            }
        }
        .onChange(of: value) { _, newValue in context.settings.save(newValue) }
    }

    /// 删除一行后 SwiftUI 可能还会用旧的位置读一次，越界时给个占位值，不崩溃
    private func ruleBinding(_ index: Int) -> Binding<AppModifierRule> {
        Binding(
            get: { value.appModifierRules[safe: index] ?? AppModifierRule(bundleID: "", name: "", swaps: []) },
            set: { newValue in
                if value.appModifierRules.indices.contains(index) {
                    value.appModifierRules[index] = newValue
                }
            },
        )
    }
}

private struct AppRuleSection: View {
    @Binding var rule: AppModifierRule
    let isActive: Bool
    let onDelete: () -> Void

    var body: some View {
        Section {
            ForEach(rule.swaps.indices, id: \.self) { index in
                HStack {
                    Picker("来源", selection: swapBinding(index, \.from)) {
                        ForEach(ModifierSwap.sources, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Picker("目标", selection: swapBinding(index, \.to)) {
                        ForEach(ModifierSwap.targets, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    DeleteButton {
                        if rule.swaps.indices.contains(index) {
                            rule.swaps.remove(at: index)
                        }
                    }
                }
            }
            HStack {
                Button("添加一条") { rule.swaps.append(nextSwap()) }
                Button("⌘ ⌃ 对调") { rule.swaps = ModifierSwap.commandControl }
                Spacer()
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack {
            Toggle("启用", isOn: $rule.isEnabled).labelsHidden()
            AppIcon(bundleID: rule.bundleID)
            Text(rule.name.isEmpty ? rule.bundleID : rule.name)
            Text(rule.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if isActive {
                Text("生效中").font(.caption).foregroundStyle(.green)
            }
            Spacer()
            DeleteButton(action: onDelete)
        }
    }

    private func swapBinding<Value>(_ index: Int, _ path: WritableKeyPath<ModifierSwap, Value>) -> Binding<Value> {
        Binding(
            get: { (rule.swaps.indices.contains(index) ? rule.swaps[index] : ModifierSwap.commandControl[0])[keyPath: path] },
            set: { newValue in
                if rule.swaps.indices.contains(index) {
                    rule.swaps[index][keyPath: path] = newValue
                }
            },
        )
    }

    private func nextSwap() -> ModifierSwap {
        let used = Set(rule.swaps.map(\.from))
        let from = ModifierSwap.sources.first { !used.contains($0) } ?? .command
        return ModifierSwap(from: from, to: from == .control ? .command : .control)
    }
}

/// 添加规则：从运行中的 App 选，或者选一个 .app（可以进到包里，选游戏本体）
private struct AddAppMenu: View {
    let onPick: (_ bundleID: String, _ name: String) -> Void

    var body: some View {
        Menu("添加 App") {
            Section("运行中的 App") {
                ForEach(Self.runningApps(), id: \.bundleID) { app in
                    Button(app.name) { onPick(app.bundleID, app.name) }
                }
            }
            Divider()
            Button("选择 App…") { chooseApp() }
        }
        .fixedSize()
    }

    private static func runningApps() -> [(bundleID: String, name: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.message = "游戏本体可能在启动器的包里面，例如 League of Legends.app/Contents/LoL/Game/"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        onPick(id, name)
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import MAIOKit
import MAIOUI
import SwiftUI

/// 按键映射的设置：Super Caps（全局 Caps 分层）、键盘重映射（设备级修饰键）、其他改键（全局键盘改键、鼠标按键）。
struct KeysSettingsView: View {
    enum Page: String, CaseIterable {
        case capsLayer = "Super Caps"
        case keyboards = "键盘重映射"
        case remaps = "其他改键"
    }

    let context: any FeatureContext
    /// 功能没在运行时为 nil
    let remaps: RemapController?
    @State private var page = Page.capsLayer

    var body: some View {
        Picker("页面", selection: $page) {
            ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        switch page {
        case .keyboards: KeyboardsPage()
        case .capsLayer: CapsLayerPage(context: context, controller: remaps)
        case .remaps: RemapsPage(context: context)
        }
    }
}

/// 设备级：选一个接着的键盘，改它的修饰键。和系统设置的"修饰键"是同一份设置。
struct KeyboardsPage: View {
    @State private var model = KeyboardsModel()

    var body: some View {
        Group {
            PageIntro(
                symbol: "keyboard",
                title: "键盘重映射",
                text: "为每个键盘单独调换修饰键。例如外接 Windows 键盘时，把 Alt / Win 换成和 Mac 一样的 ⌥ / ⌘ 位置。",
            )
            if model.karabinerRunning {
                Section {
                    Label(
                        "Karabiner 正在运行，它会接管键盘，这里的改动对实体键盘不起作用。请先退出 Karabiner。",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(.orange)
                }
            }
            Section {
                if model.devices.isEmpty {
                    Text(model.isAvailable ? "没有找到键盘" : "读不到系统的键盘服务").foregroundStyle(.secondary)
                } else {
                    Picker("键盘", selection: $model.selection) {
                        ForEach(model.devices) { device in
                            Text(device.displayName).tag(Optional(device.key))
                        }
                    }
                }
            } header: {
                Text("键盘")
            } footer: {
                NoteLines(
                    "只列出当前连接的键盘，每个键盘的设置分开保存。",
                    "未连接的键盘设置仍保存在系统里，接上后自动生效。",
                )
            }
            if model.selection != nil {
                modifierSection
            }
        }
        .task { await model.watch() }
    }

    private var modifierSection: some View {
        Section {
            ForEach(ModifierKey.allCases, id: \.self) { key in
                Picker(key.title, selection: model.binding(for: key)) {
                    ForEach(ModifierTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            HStack {
                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("还原默认") { model.restoreDefaults() }
                    .disabled(model.mapping.isDefault)
            }
        } header: {
            Text("修饰键")
        } footer: {
            NoteLines(
                "改动立即生效，退出 MAIO 后依然有效。",
                "与系统设置「键盘 › 键盘快捷键… › 修饰键」是同一份设置。",
                "系统设置的窗口开着时，需要重新打开才能看到变化。",
            )
        }
    }
}

/// 键盘页的状态：键盘列表每 2 秒刷新一次（插拔），选中键盘的映射从系统读。
@MainActor
@Observable
final class KeyboardsModel {
    private let keyboards = HIDKeyboards()
    private var store: ModifierMappingStore {
        ModifierMappingStore(keyboards: keyboards)
    }

    private(set) var devices: [KeyboardDevice] = []
    private(set) var mapping = ModifierMapping(pairs: [])
    private(set) var karabinerRunning = false
    private(set) var message: String?
    var selection: DeviceKey? {
        didSet {
            if selection != oldValue {
                reloadMapping()
            }
        }
    }

    var isAvailable: Bool {
        keyboards.isAvailable
    }

    func watch() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func binding(for key: ModifierKey) -> Binding<ModifierTarget> {
        Binding(
            get: { self.mapping.target(for: key) },
            set: { target in
                var mapping = self.mapping
                mapping.set(key, to: target)
                self.save(mapping)
            },
        )
    }

    func restoreDefaults() {
        save(ModifierMapping(pairs: []))
    }

    private func refresh() {
        karabinerRunning = KarabinerDetector.isRunning()
        let latest = keyboards.keyboards()
        guard latest != devices else { return }
        devices = latest
        if selection.map({ key in !latest.contains { $0.key == key } }) ?? true {
            selection = latest.first?.key
        }
    }

    private func reloadMapping() {
        message = nil
        mapping = selection.map(store.mapping(for:)) ?? ModifierMapping(pairs: [])
    }

    private func save(_ mapping: ModifierMapping) {
        guard let selection else { return }
        self.mapping = mapping
        message = store.save(mapping, for: selection) ? nil : "已保存，但没能立即生效：重新接上键盘后生效"
    }
}

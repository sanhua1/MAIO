import MAIOKit
import MAIOUI
import SwiftUI

/// Finder 隐藏设置：直接读写 Finder 自己的配置，重启 Finder 后生效。
struct FinderTweaksPage: View {
    let backups: FinderBackups?
    @Binding var restart: RestartState
    @State private var hasBackups = false
    @State private var confirmingRestore = false
    /// 各项的当前状态（每次打开都直接读 Finder 的配置）
    @State private var tweaks: [String: Bool] = [:]
    @State private var viewStyle = FinderViewStyle.system

    var body: some View {
        Group {
            Text("直接修改 Finder 自己的设置；关闭某项会恢复系统默认。")
                .font(.caption).foregroundStyle(.secondary)
            Picker(selection: $viewStyle) {
                ForEach(FinderViewStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                LabelWithInfo("新窗口默认显示方式", info: FinderHelp.viewStyle)
            }
            .onChange(of: viewStyle) { _, style in
                let current = FinderPreferences.value(FinderViewStyle.key, in: .finder)
                let target: PreferenceValue? = style == .system ? nil : .string(style.rawValue)
                guard current != target else { return }
                backups?.rememberPreference(FinderViewStyle.key, in: .finder)
                FinderPreferences.write(FinderViewStyle.key, value: target, in: .finder)
                restart.needed = true
            }
            group("显示", FinderTweaks.display)
            group("行为", FinderTweaks.behavior)
            group("文件", FinderTweaks.files)
            restoreRow
        }
        .onAppear(perform: reload)
        .confirmationDialog("还原 MAIO 对 Finder 做过的所有修改？", isPresented: $confirmingRestore) {
            Button("还原") {
                backups?.restoreAll()
                restart.needed = true
                reload()
            }
        } message: {
            Text("隐藏设置和原生快捷键都回到 MAIO 第一次修改之前的样子（包括你在 MAIO 之前自己改过的值），之后要重启 Finder。")
        }
    }

    @ViewBuilder private func group(_ title: String, _ items: [FinderTweak]) -> some View {
        Text(title).font(.headline).padding(.top, 6)
        ForEach(items) { tweak in
            Toggle(isOn: binding(for: tweak)) {
                if tweak.info.isEmpty {
                    Text(tweak.title)
                } else {
                    LabelWithInfo(tweak.title, info: tweak.info)
                }
            }
        }
    }

    private func binding(for tweak: FinderTweak) -> Binding<Bool> {
        Binding(
            get: { tweaks[tweak.id] ?? false },
            set: { on in
                backups?.rememberTweak(tweak)
                FinderPreferences.set(tweak, on: on)
                tweaks[tweak.id] = on
                restart.needed = true
                restart.needsRelogin = restart.needsRelogin || tweak.needsRelogin
            },
        )
    }

    private var restoreRow: some View {
        LabeledContent {
            Button("全部还原…") { confirmingRestore = true }.disabled(!hasBackups)
        } label: {
            Text("还原 MAIO 做过的修改")
            Text("隐藏设置和原生快捷键。停用或卸载 MAIO 前可以先还原。").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private func reload() {
        hasBackups = backups?.hasBackups ?? false
        tweaks = Dictionary(uniqueKeysWithValues: FinderTweaks.all.map { ($0.id, $0.isOn(FinderPreferences.value($0))) })
        if case let .string(raw) = FinderPreferences.value(FinderViewStyle.key, in: .finder) {
            viewStyle = FinderViewStyle(rawValue: raw) ?? .system
        }
    }
}

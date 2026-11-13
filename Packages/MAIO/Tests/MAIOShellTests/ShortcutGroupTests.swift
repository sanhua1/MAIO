import MAIOKit
@testable import MAIOShell
import Testing

@MainActor
struct ShortcutGroupTests {
    private let catalog = [
        FeatureManifest(
            id: "system", displayName: "系统", symbol: "gear", summary: "",
            commands: [
                CommandDescriptor(id: "system.openApp", title: "打开 App"),
                CommandDescriptor(id: "system.openURL", title: "打开网址"),
            ],
        ),
        FeatureManifest(
            id: "clipboard", displayName: "剪贴板", symbol: "doc.on.clipboard", summary: "",
            commands: [CommandDescriptor(id: "clipboard.show", title: "显示")],
        ),
        FeatureManifest(
            id: "translate", displayName: "翻译", symbol: "character.book.closed", summary: "",
            commands: [CommandDescriptor(id: "translate.show", title: "翻译")],
        ),
    ]

    private func binding(_ id: String, _ command: CommandID) -> CommandBinding {
        CommandBinding(id: id, trigger: .hotkey(KeyChord(keyCode: 0, modifiers: [.option])), command: command)
    }

    @Test func `groups by feature in catalog order then apps and actions`() {
        let bindings = [
            binding("url", "system.openURL"),
            binding("t1", "translate.show"),
            binding("app", "system.openApp"),
            binding("c1", "clipboard.show"),
            binding("x", "gone.command"),
            binding("t2", "translate.show"),
        ]
        let groups = ShortcutGroup.make(bindings, catalog: catalog)
        #expect(groups.map(\.title) == ["剪贴板", "翻译", "未知命令", "打开 App", "其他动作"])
        #expect(groups[1].bindings.map(\.id) == ["t1", "t2"])
        #expect(groups.map(\.isFeature) == [true, true, false, false, false])
    }

    @Test func `empty groups are omitted`() {
        let groups = ShortcutGroup.make([binding("c1", "clipboard.show")], catalog: catalog)
        #expect(groups.map(\.id) == ["clipboard"])
    }
}

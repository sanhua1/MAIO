@testable import FeatureLauncher
import Foundation
import MAIOKit
import Testing

struct CommandSourceTests {
    private static let maio = [
        AvailableCommand(
            descriptor: CommandDescriptor(id: "screenshot.history", title: "截图历史"),
            featureID: "screenshot", featureName: "截图", featureSymbol: "camera",
        ),
        AvailableCommand(
            descriptor: CommandDescriptor(
                id: "system.openApp", title: "打开 App",
                parameters: [ParameterSpec(key: "app", title: "App", kind: .application)],
            ),
            featureID: "system", featureName: "系统操作", featureSymbol: "gearshape",
        ),
        AvailableCommand(
            descriptor: CommandDescriptor(id: "launcher.show", title: "启动器"),
            featureID: "launcher", featureName: "启动器", featureSymbol: "magnifyingglass",
        ),
    ]
    private static let panes = [
        SettingsPane(id: "com.apple.BluetoothSettings", name: "蓝牙", otherNames: ["Bluetooth"], path: "/x.appex", iconType: nil),
    ]

    private var commands: [LauncherItem] {
        CommandList.items(maio: Self.maio, panes: Self.panes, own: "launcher")
    }

    private func ranking(_ commands: [LauncherItem], usage: UsageBook = UsageBook()) -> LauncherRanking {
        LauncherRanking(apps: [], commands: commands, usage: usage, running: [], settings: .defaultValue, now: Date())
    }

    @Test func `skips own commands and ones needing arguments`() {
        let ids = commands.map(\.id)
        #expect(ids.contains("command:screenshot.history"))
        #expect(!ids.contains("command:system.openApp"), "有必填参数的不列出")
        #expect(!ids.contains("command:launcher.show"), "不列出启动器自己的命令")
        #expect(ids.contains("system:lockScreen"))
        #expect(ids.last == "settings:com.apple.BluetoothSettings")
    }

    @Test func `finds commands by pinyin english and feature name`() {
        let ranking = ranking(commands)
        #expect(ranking.rank(commands, "suoping", limit: 3).first?.id == "system:lockScreen")
        #expect(ranking.rank(commands, "bluetooth", limit: 3).first?.id == "settings:com.apple.BluetoothSettings")
        #expect(ranking.rank(commands, "ly", limit: 3).first?.id == "settings:com.apple.BluetoothSettings")
        #expect(ranking.rank(commands, "jt ls", limit: 3).first?.id == "command:screenshot.history")
    }

    @Test func `all mode shows a few commands after apps`() {
        let sections = ranking(commands).sections(for: LauncherQuery(source: .all, text: "锁", engine: nil))
        #expect(sections.first?.title == "命令")
        #expect(sections.first?.items.count ?? 0 <= LauncherRanking.maxCommandsInAll)
    }

    @Test func `empty command source lists recent then groups without duplicates`() {
        var usage = UsageBook()
        usage.record("system:sleep", query: "", at: Date())
        let sections = ranking(commands, usage: usage).sections(for: LauncherQuery(source: .commands, text: "", engine: nil))
        #expect(sections.map(\.title) == ["最近使用", "MAIO 命令", "系统操作", "系统设置"])
        let ids = sections.flatMap(\.items).map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test func `prefix selects commands and tab cycles to them`() {
        let query = LauncherQuery.parse(">蓝牙", selected: .all, engines: [])
        #expect(query.source == .commands)
        #expect(query.text == "蓝牙")
        #expect(LauncherSource.available.last == .commands)
    }
}

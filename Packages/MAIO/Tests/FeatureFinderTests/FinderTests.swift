@testable import FeatureFinder
import MAIOKit
import MAIOTesting
import Testing

@MainActor
struct FinderFeatureTests {
    @Test func `registers commands, key filter and reserved keys`() async throws {
        let context = FakeFeatureContext(featureID: "finder")
        let feature = FinderFeature(context: context)
        try await feature.activate()
        #expect(Set(context.fakeCommands.descriptors.keys) == Set(FinderFeature.manifest.commands.map(\.id)))
        #expect(context.fakeInput.keyFilters.count == 1)
        let reserved = context.fakeShortcuts.reserved
        #expect(reserved.contains { $0.chord == chord("cmd+x") && $0.scope == .onlyIn([FinderKeymap.bundleID]) })
        #expect(!reserved.contains { $0.title == "前进" }, "没设快捷键的动作不登记")
        await feature.deactivate()
        #expect(context.fakeInput.keyFilters.isEmpty)
    }
}

@MainActor
struct FinderKeyFilterTests {
    @Test func `filter reports actions and honours editing`() async {
        let filter = FinderKeyFilter(config: FinderSettings.defaultValue.keyConfig(menu: []))
        let environment = RealtimeEnvironment(frontmostBundleID: FinderKeymap.bundleID, modifiers: [])
        let newFile = KeyEvent(kind: .down, keyCode: FinderKeymap.Key.n, modifiers: [.command, .option])
        #expect(filter.process(newFile, environment) == .consume)
        filter.finish()
        var received: [FinderAction] = []
        for await action in filter.actions {
            received.append(action)
        }
        #expect(received == [.newTextFile])

        let enter = KeyEvent(kind: .down, keyCode: FinderKeymap.Key.returnKey, modifiers: [])
        filter.setEditing(true)
        #expect(filter.process(enter, environment) == .pass)
        filter.setEditing(false)
        #expect(filter.process(enter, environment) != .pass)
        filter.update(.off)
        #expect(filter.process(enter, environment) == .pass)
    }
}

struct MenuShortcutTests {
    @Test func `accessibility attributes become chords`() {
        // ⇧⌘N：字符 N，修饰键位 1（⇧）
        #expect(MenuShortcuts.chord(character: "N", modifiers: 1, virtualKey: nil)?.chord == chord("cmd+shift+n"))
        // ⌘⌫：字符 U+0008，键码 51
        #expect(MenuShortcuts.chord(character: "\u{8}", modifiers: 0, virtualKey: 51)?.chord == chord("cmd+delete"))
        // ⌃⌘↑
        #expect(MenuShortcuts.chord(character: "\u{F700}", modifiers: 4, virtualKey: 126)?.chord == chord("ctrl+cmd+up"))
        // ⌃⇧⇥（没有 ⌘：位 8）
        #expect(MenuShortcuts.chord(character: "\t", modifiers: 13, virtualKey: 48)?.chord == chord("ctrl+shift+tab"))
        // 🌐F：位 16 + 8
        let globe = MenuShortcuts.chord(character: "F", modifiers: 24, virtualKey: nil)
        #expect(globe?.isGlobe == true)
        #expect(globe?.chord == chord("fn+f"))
        #expect(MenuShortcuts.chord(character: "", modifiers: 0, virtualKey: nil) == nil)
    }

    @Test func `user key equivalents round trip`() {
        for text in ["cmd+shift+n", "ctrl+opt+cmd+c", "cmd+up", "cmd+delete", "cmd+[", "ctrl+cmd+f5", "shift+cmd+space"] {
            let original = chord(text)
            let encoded = MenuShortcuts.encode(original)
            #expect(encoded.flatMap(MenuShortcuts.decode) == original, "\(text) → \(encoded ?? "nil")")
        }
        #expect(MenuShortcuts.encode(chord("cmd+shift+n")) == "@$n")
        #expect(MenuShortcuts.decode("@~^$\u{F701}") == chord("ctrl+opt+shift+cmd+down"))
        #expect(MenuShortcuts.decode("@") == nil)
    }

    @Test func `preference keys use escaped menu paths`() {
        let key = MenuShortcuts.preferenceKey(["显示", "排序方式", "种类"])
        #expect(key == "\u{1B}显示\u{1B}排序方式\u{1B}种类")
        #expect(MenuShortcuts.path(fromPreferenceKey: key) == ["显示", "排序方式", "种类"])
        #expect(MenuShortcuts.path(fromPreferenceKey: "新建文件夹") == ["新建文件夹"])
    }
}

struct FinderConflictTests {
    private let menu = [
        FinderMenuItem(path: ["显示", "隐藏工具栏"], chord: chord("cmd+opt+t")),
        FinderMenuItem(path: ["编辑", "粘贴"], chord: chord("cmd+v")),
        FinderMenuItem(path: ["文件", "新建文件夹"], chord: chord("cmd+shift+n")),
    ]

    @Test func `action conflicts`() {
        let settings = FinderSettings.defaultValue
        let terminal = FinderConflicts.forAction(
            .openTerminal, chord: chord("cmd+opt+t"), settings: settings, menu: menu, external: [],
        )
        #expect(terminal.map(\.level) == [.warning])
        let paste = FinderConflicts.forAction(.paste, chord: chord("cmd+v"), settings: settings, menu: menu, external: [])
        #expect(paste.map(\.level) == [.info])
        let duplicate = FinderConflicts.forAction(.forward, chord: chord("cmd+x"), settings: settings, menu: menu, external: [])
        #expect(duplicate.first?.level == .error)
        let system = FinderConflicts.forAction(
            .forward, chord: chord("cmd+space"), settings: settings, menu: menu,
            external: [ShortcutOccupant(kind: .system, title: "聚焦搜索")],
        )
        #expect(system.first?.level == .error)
        let letter = FinderConflicts.forAction(.forward, chord: chord("k"), settings: settings, menu: menu, external: [])
        #expect(letter.map(\.level) == [.warning], "不带修饰键的字母会影响按名称跳转")
    }

    @Test func `menu item conflicts`() {
        let settings = FinderSettings.defaultValue
        let folder = menu[2]
        #expect(FinderConflicts.forMenuItem(folder, chord: chord("cmd+shift+n"), settings: settings, menu: menu, external: [])
            .isEmpty)
        let stolen = FinderConflicts.forMenuItem(folder, chord: chord("cmd+x"), settings: settings, menu: menu, external: [])
        #expect(stolen.first?.level == .error)
        let duplicate = FinderConflicts.forMenuItem(
            folder,
            chord: chord("cmd+opt+t"),
            settings: settings,
            menu: menu,
            external: [],
        )
        #expect(duplicate.contains { $0.text.contains("隐藏工具栏") })
    }
}

struct FinderTweakTests {
    @Test func `values are normalized`() {
        #expect(PreferenceValue.normalized(true) == .bool(true))
        #expect(PreferenceValue.normalized(0) == .bool(false))
        #expect(PreferenceValue.normalized("YES") == .bool(true))
        #expect(PreferenceValue.normalized("false") == .bool(false))
        #expect(PreferenceValue.normalized("SCcf") == .string("SCcf"))
        #expect(PreferenceValue.normalized(nil) == nil)
    }

    @Test func `tweak ids are unique and on state matches value`() {
        #expect(Set(FinderTweaks.all.map(\.id)).count == FinderTweaks.all.count)
        let warning = FinderTweaks.all.first { $0.id == "noExtensionWarning" }
        #expect(warning?.isOn(.bool(false)) == true)
        #expect(warning?.isOn(nil) == false)
    }

    @Test func `file name split and escaping`() {
        #expect(FinderScripting.split("新建文本文档.txt") == ("新建文本文档", ".txt"))
        #expect(FinderScripting.split("README") == ("README", ""))
        #expect(FinderScripting.split(".env") == (".env", ""))
        #expect(FinderScripting.escape("a\"b\\c") == "a\\\"b\\\\c")
    }
}

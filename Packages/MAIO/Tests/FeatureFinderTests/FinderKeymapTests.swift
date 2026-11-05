@testable import FeatureFinder
import MAIOKit
import Testing

/// "cmd+x" → KeyChord（测试用，解析失败时返回一个不会匹配的键）
func chord(_ text: String) -> KeyChord {
    KeyChord(string: text) ?? KeyChord(keyCode: 999, modifiers: [])
}

struct FinderKeymapTests {
    private let config = FinderSettings.defaultValue.keyConfig(menu: [])

    private func key(_ text: String, kind: KeyEvent.Kind = .down, repeat isRepeat: Bool = false) -> KeyEvent {
        let parsed = chord(text)
        return KeyEvent(kind: kind, keyCode: parsed.keyCode, modifiers: parsed.modifiers, isRepeat: isRepeat)
    }

    private func decide(
        _ text: String, config: FinderKeyConfig? = nil, state: inout FinderKeyState,
        frontmost: String? = FinderKeymap.bundleID, isRepeat: Bool = false,
    ) -> FinderKeymap.Result {
        FinderKeymap.decide(key(text, repeat: isRepeat), frontmost: frontmost, config: config ?? self.config, state: &state)
    }

    private func decide(_ text: String, config: FinderKeyConfig? = nil, isRepeat: Bool = false) -> FinderKeymap.Result {
        var state = FinderKeyState()
        return decide(text, config: config, state: &state, isRepeat: isRepeat)
    }

    private func replaced(_ text: String) -> FinderKeymap.Result {
        FinderKeymap.Result(decision: .replace(chord(text)))
    }

    @Test func `default windows style keys use fallback targets`() {
        #expect(decide("return") == replaced("cmd+down"))
        #expect(decide("key76") == replaced("cmd+down"), "小键盘 Enter 等同回车")
        #expect(decide("f2") == replaced("return"))
        #expect(decide("fn+f2") == replaced("return"))
        #expect(decide("forwarddelete") == replaced("cmd+delete"))
        #expect(decide("fn+forwarddelete") == replaced("cmd+delete"))
        #expect(decide("delete") == replaced("cmd+["))
        #expect(decide("opt+up") == replaced("cmd+up"))
        #expect(decide("cmd+l").decision == .replace(chord("cmd+shift+g")))
        #expect(decide("opt+right") == .pass, "前进默认不设（⌥→ 是列表视图的展开全部）")
        #expect(decide("a") == .pass)
        #expect(decide("shift+return") == .pass)
    }

    @Test func `targets follow finder menu shortcuts`() {
        let menu = [
            FinderMenuItem(path: ["前往", "返回"], chord: chord("ctrl+cmd+b")),
            FinderMenuItem(path: ["文件", "打开"], chord: chord("cmd+o")),
        ]
        let config = FinderSettings.defaultValue.keyConfig(menu: menu, overrides: [["文件", "打开"]: chord("cmd+shift+o")])
        #expect(decide("delete", config: config) == replaced("ctrl+cmd+b"))
        #expect(decide("return", config: config) == replaced("cmd+shift+o"), "还没重启生效的修改优先")
    }

    @Test func `custom and disabled shortcuts`() {
        var settings = FinderSettings.defaultValue
        settings.update(.back) { $0.chord = chord("opt+left") }
        settings.update(.open) { $0.isEnabled = false }
        let config = settings.keyConfig(menu: [])
        #expect(decide("opt+left", config: config) == replaced("cmd+["))
        #expect(decide("delete", config: config) == .pass)
        #expect(decide("return", config: config) == .pass)
        #expect(settings.shortcuts.count == 2)
        settings.update(.open) { $0.isEnabled = true }
        #expect(settings.shortcuts.count == 1, "恢复默认值的行不写进设置")
    }

    @Test func `holding return does not open repeatedly but back repeats`() {
        #expect(decide("return", isRepeat: true) == .init(decision: .consume))
        #expect(decide("delete", isRepeat: true) == replaced("cmd+["))
    }

    @Test func `passes outside finder and while editing`() {
        var state = FinderKeyState()
        #expect(decide("return", state: &state, frontmost: "com.apple.Safari") == .pass)
        #expect(decide("return", state: &state, frontmost: nil) == .pass)
        state.isEditing = true
        #expect(decide("return", state: &state) == .pass)
        #expect(decide("delete", state: &state) == .pass)
        #expect(decide("cmd+x", state: &state).decision == .pass)
    }

    @Test func `switches turn each key off`() {
        for text in ["return", "f2", "forwarddelete", "delete", "cmd+x", "opt+up", "cmd+l", "cmd+opt+n", "cmd+opt+t"] {
            #expect(decide(text, config: .off) == .pass, "\(text)")
        }
    }

    @Test func `cut then paste moves once`() {
        var state = FinderKeyState()
        #expect(decide("cmd+x", state: &state) == .init(decision: .consume, action: .cut(copy: chord("cmd+c"))))
        // 剪切由主线程确认剪贴板真的变了以后才标记
        #expect(decide("cmd+v", state: &state).decision == .pass)
        state.cutPending = true
        #expect(decide("cmd+v", state: &state).decision == .replace(chord("cmd+opt+v")))
        #expect(state.cutPending == false)
        #expect(decide("cmd+v", state: &state).decision == .pass)
    }

    @Test func `copy cancels pending cut`() {
        var state = FinderKeyState(cutPending: true)
        #expect(decide("cmd+c", state: &state).decision == .pass)
        #expect(state.cutPending == false)
        #expect(decide("cmd+v", state: &state).decision == .pass)
    }

    @Test func `extra actions`() {
        #expect(decide("cmd+opt+n").action == .newTextFile)
        #expect(decide("cmd+opt+t").action == .openTerminal)
        #expect(decide("cmd+opt+t", isRepeat: true) == .init(decision: .consume, action: .keyWhileCommand))
    }

    @Test func `cheat sheet events`() {
        var state = FinderKeyState()
        let flags = KeyEvent(kind: .flagsChanged, keyCode: 55, modifiers: .command)
        #expect(FinderKeymap.decide(flags, frontmost: FinderKeymap.bundleID, config: config, state: &state)
            == .init(decision: .pass, action: .modifiers(.command)))
        #expect(FinderKeymap.decide(flags, frontmost: "com.apple.Safari", config: config, state: &state) == .pass)
        #expect(decide("cmd+a") == .init(decision: .pass, action: .keyWhileCommand))
        #expect(decide("a").action == nil)
        var off = config
        off.cheatSheet = false
        #expect(FinderKeymap.decide(flags, frontmost: FinderKeymap.bundleID, config: off, state: &state) == .pass)
    }
}

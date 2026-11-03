import Darwin
@testable import MAIOCore
import MAIOKit
import Testing

struct KeyNormalizerTests {
    private let fnFlag = KeyNormalizer.functionMask

    @Test func `tracks physical function key`() {
        var normalizer = KeyNormalizer()
        _ = normalizer.normalize(kind: .flagsChanged, keyCode: KeyCodes.function, flags: fnFlag, isRepeat: false)
        let event = normalizer.normalize(kind: .down, keyCode: 0, flags: fnFlag, isRepeat: false)
        #expect(event.chord == KeyChord(string: "fn+a"))
        _ = normalizer.normalize(kind: .flagsChanged, keyCode: KeyCodes.function, flags: 0, isRepeat: false)
        #expect(normalizer.normalize(kind: .down, keyCode: 0, flags: 0, isRepeat: false).modifiers.isEmpty)
    }

    @Test func `ignores implicit function flag on arrow keys`() {
        var normalizer = KeyNormalizer()
        // 方向键自带 Fn 标志位，但用户没有按 Fn
        let event = normalizer.normalize(kind: .down, keyCode: 123, flags: fnFlag | KeyNormalizer.commandMask, isRepeat: false)
        #expect(event.chord == KeyChord(string: "cmd+left"))
    }

    @Test func `trusts function flag on letters without flags changed`() {
        var normalizer = KeyNormalizer()
        #expect(normalizer.normalize(kind: .down, keyCode: 0, flags: fnFlag, isRepeat: false).modifiers == .function)
    }
}

struct KeyboardRouterTests {
    private func binding(_ chord: String, scope: BindingScope = .global, id: String = "b") -> CommandBinding {
        CommandBinding(id: id, trigger: .hotkey(KeyChord(string: chord)!), command: "system.openApp", scope: scope)
    }

    private func key(_ chord: String, _ kind: KeyEvent.Kind = .down, isRepeat: Bool = false) -> KeyEvent {
        let parsed = KeyChord(string: chord)!
        return KeyEvent(kind: kind, keyCode: parsed.keyCode, modifiers: parsed.modifiers, isRepeat: isRepeat)
    }

    @Test func `fires and swallows matching key up`() {
        var router = KeyboardRouter()
        let target = binding("fn+a")
        router.table = HotkeyTable(bindings: [target]) { _ in true }
        #expect(router.route(key("fn+a")) == .init(consume: true, effect: .fire(target)))
        #expect(router.route(key("fn+a", isRepeat: true)) == .swallow)
        #expect(router.route(key("a", .up)) == .swallow)
        #expect(router.route(key("a", .up)) == .pass)
    }

    @Test func `passes unbound keys`() {
        var router = KeyboardRouter()
        router.table = HotkeyTable(bindings: [binding("fn+a")]) { _ in true }
        #expect(router.route(key("a")) == .pass)
        #expect(router.route(key("cmd+a")) == .pass)
    }

    @Test func `skips unavailable and disabled bindings`() {
        var router = KeyboardRouter()
        var disabled = binding("fn+b", id: "d")
        disabled.isEnabled = false
        router.table = HotkeyTable(bindings: [binding("fn+a"), disabled]) { _ in false }
        #expect(router.route(key("fn+a")) == .pass)
        router.table = HotkeyTable(bindings: [disabled]) { _ in true }
        #expect(router.route(key("fn+b")) == .pass)
    }

    @Test func `app specific binding wins`() {
        var router = KeyboardRouter()
        let global = binding("fn+a", id: "global")
        let terminal = binding("fn+a", scope: .onlyIn(["com.apple.Terminal"]), id: "terminal")
        router.table = HotkeyTable(bindings: [global, terminal]) { _ in true }
        router.frontmost = "com.apple.Terminal"
        #expect(router.route(key("fn+a")).effect == .fire(terminal))
        router.frontmost = "com.apple.Safari"
        #expect(router.route(key("fn+a")).effect == .fire(global))
    }

    @Test func `recording captures instead of firing`() throws {
        var router = KeyboardRouter()
        router.table = HotkeyTable(bindings: [binding("fn+a")]) { _ in true }
        router.isRecording = true
        #expect(try router.route(key("fn+a")) == .init(consume: true, effect: .toRecorder(#require(KeyChord(string: "fn+a")))))
        #expect(router.route(key("a", .up)) == .swallow)
    }

    @Test func `session receives everything`() {
        var router = KeyboardRouter()
        router.table = HotkeyTable(bindings: [binding("fn+a")]) { _ in true }
        router.hasSession = true
        let down = key("opt+tab")
        #expect(router.route(down) == .init(consume: true, effect: .toSession(down)))
        let flags = KeyEvent(kind: .flagsChanged, keyCode: 58, modifiers: [])
        #expect(router.route(flags) == .init(consume: false, effect: .toSession(flags)))
    }
}

struct KeyboardRouterSessionTests {
    @Test func `key released during session is not swallowed again afterwards`() throws {
        var router = KeyboardRouter()
        let tab = try #require(KeyChord(string: "opt+tab"))
        router
            .table = HotkeyTable(bindings: [CommandBinding(id: "s", trigger: .hotkey(tab), command: "switcher.show")]) { _ in
                true
            }
        _ = router.route(KeyEvent(kind: .down, keyCode: tab.keyCode, modifiers: tab.modifiers))
        router.hasSession = true
        _ = router.route(KeyEvent(kind: .up, keyCode: tab.keyCode, modifiers: tab.modifiers))
        router.hasSession = false
        #expect(router.route(KeyEvent(kind: .up, keyCode: tab.keyCode, modifiers: [])) == .pass)
    }
}

struct RemoteControlSourceTests {
    @Test func `matches remote control executables`() {
        #expect(RemoteControlSource.matches(executablePath: "/Applications/UURemote.app/Contents/Helpers/UURemoteServer"))
        #expect(RemoteControlSource
            .matches(
                executablePath: "/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd",
            ))
        #expect(RemoteControlSource.matches(executablePath: "/Applications/ToDesk.app/Contents/MacOS/ToDesk_Service"))
    }

    @Test func `ignores ordinary processes`() {
        #expect(!RemoteControlSource
            .matches(executablePath: "/Applications/Logi Options+.app/Contents/MacOS/logioptionsplus_agent"))
        #expect(!RemoteControlSource.matches(executablePath: "/System/Library/CoreServices/WindowServer"))
    }

    @Test func `hardware and own events are not remote`() {
        let cache = RemoteSourceCache()
        #expect(!cache.isRemote(0))
        #expect(!cache.isRemote(getpid()))
    }
}

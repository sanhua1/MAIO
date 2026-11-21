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

/// 按键过滤器（ADR-0017）：只在前台是指定 App 时把 a 改成 b、吞掉 c
private struct SampleKeyFilter: RealtimeKeyFilter {
    func process(_ event: KeyEvent, _ environment: RealtimeEnvironment) -> KeyFilterDecision {
        guard environment.frontmostBundleID == "com.apple.finder" else { return .pass }
        switch event.keyCode {
        case KeyChord(string: "a")?.keyCode: return .replace(KeyChord(string: "cmd+b")!)
        case KeyChord(string: "c")?.keyCode: return .consume
        default: return .pass
        }
    }
}

struct KeyFilterRoutingTests {
    private func key(_ chord: String, _ kind: KeyEvent.Kind = .down) -> KeyEvent {
        let parsed = KeyChord(string: chord)!
        return KeyEvent(kind: kind, keyCode: parsed.keyCode, modifiers: parsed.modifiers)
    }

    private func router(frontmost: String?) -> KeyboardRouter {
        var router = KeyboardRouter()
        router.frontmost = frontmost
        router.filters = [KeyFilterEntry(token: FilterToken(rawValue: 1), filter: SampleKeyFilter())]
        return router
    }

    @Test func `replace posts chord and swallows key up`() throws {
        var router = router(frontmost: "com.apple.finder")
        #expect(try router.route(key("a")) == .init(consume: true, effect: .post(#require(KeyChord(string: "cmd+b")))))
        #expect(router.route(key("a", .up)) == .swallow)
        #expect(router.route(key("c")) == .swallow)
        #expect(router.route(key("c", .up)) == .swallow)
        #expect(router.route(key("d")) == .pass)
    }

    @Test func `filters see frontmost app`() {
        var router = router(frontmost: "com.apple.Safari")
        #expect(router.route(key("a")) == .pass)
    }

    @Test func `filters run before bindings but not during sessions`() throws {
        var router = router(frontmost: "com.apple.finder")
        let binding = try CommandBinding(id: "b", trigger: .hotkey(#require(KeyChord(string: "a"))), command: "system.openApp")
        router.table = HotkeyTable(bindings: [binding]) { _ in true }
        #expect(try router.route(key("a")) == .init(consume: true, effect: .post(#require(KeyChord(string: "cmd+b")))))
        router.hasSession = true
        #expect(router.route(key("a")) == .init(consume: true, effect: .toSession(key("a"))))
    }

    @Test func `session filters hand remapped keys to the session`() {
        var router = KeyboardRouter()
        router.filters = [KeyFilterEntry(token: FilterToken(rawValue: 1), filter: SessionKeyFilter())]
        router.hasSession = true
        // ⌥ 按着（例如 ⌥Tab 切换窗口中），w 改成 ↑，修饰键保留
        #expect(router.route(key("opt+w")) == .init(consume: true, effect: .toSession(key("opt+up"))))
        #expect(router.route(key("opt+w", .up)) == .init(consume: true, effect: .toSession(key("opt+up", .up))))
        #expect(router.route(key("opt+q")) == .swallow)
        #expect(router.route(key("opt+e")) == .init(consume: true, effect: .toSession(key("opt+e"))))
    }
}

/// 选择在会话里生效的过滤器（ADR-0025）：w 改成 ↑（叠加原修饰键），吞掉 q
private struct SessionKeyFilter: RealtimeKeyFilter {
    var appliesDuringKeyboardSessions: Bool {
        true
    }

    func process(_ event: KeyEvent, _: RealtimeEnvironment) -> KeyFilterDecision {
        switch event.keyCode {
        case KeyChord(string: "w")?.keyCode: .replace(KeyChord(
                keyCode: KeyChord(string: "up")!.keyCode,
                modifiers: event.modifiers,
            ))
        case KeyChord(string: "q")?.keyCode: .consume
        default: .pass
        }
    }
}

private final class FlagsRecorder: RealtimeKeyFilter, @unchecked Sendable {
    var seen: [KeyEvent.Kind] = []
    func process(_ event: KeyEvent, _: RealtimeEnvironment) -> KeyFilterDecision {
        seen.append(event.kind)
        return .consume
    }
}

struct KeyFilterFlagsTests {
    @Test func `filters observe modifier changes but cannot swallow them`() {
        let recorder = FlagsRecorder()
        var router = KeyboardRouter()
        router.filters = [KeyFilterEntry(token: FilterToken(rawValue: 1), filter: recorder)]
        let flags = KeyEvent(kind: .flagsChanged, keyCode: 55, modifiers: .command)
        #expect(router.route(flags) == .pass)
        router.isRecording = true
        #expect(router.route(flags) == .pass)
        #expect(recorder.seen == [.flagsChanged])
    }
}

struct MediaKeyRouterTests {
    private struct Fixed: RealtimeMediaKeyFilter {
        let decision: FilterDecision
        func process(_: MediaKeyEvent) -> FilterDecision {
            decision
        }
    }

    @Test func `decodes system defined data 1`() {
        // 音量加按下：键类型 0、状态 0xA
        let down = MediaKeyRouter.decode(subtype: 8, data1: 0 << 16 | 0xA << 8)
        #expect(down?.key == .volumeUp && down?.isDown == true && down?.isRepeat == false)
        let repeatDown = MediaKeyRouter.decode(subtype: 8, data1: 1 << 16 | 0xA << 8 | 1)
        #expect(repeatDown?.key == .volumeDown && repeatDown?.isRepeat == true)
        let up = MediaKeyRouter.decode(subtype: 8, data1: 7 << 16 | 0xB << 8)
        #expect(up?.key == .mute && up?.isDown == false)
        #expect(MediaKeyRouter.decode(subtype: 8, data1: 2 << 16 | 0xA << 8)?.key == .brightnessUp)
        #expect(MediaKeyRouter.decode(subtype: 8, data1: 3 << 16 | 0xA << 8)?.key == .brightnessDown)
        // 播放键（16）、别的子类型都不管
        #expect(MediaKeyRouter.decode(subtype: 8, data1: 16 << 16 | 0xA << 8) == nil)
        #expect(MediaKeyRouter.decode(subtype: 7, data1: 0xA << 8) == nil)
    }

    @Test func `consumed down also consumes its up`() {
        var router = MediaKeyRouter()
        router.filters = [.init(token: FilterToken(rawValue: 1), filter: Fixed(decision: .consume))]
        let r1 = router.route(key: .volumeUp, isDown: true, isRepeat: false, modifiers: [])
        #expect(r1)
        let r2 = router.route(key: .volumeUp, isDown: false, isRepeat: false, modifiers: [])
        #expect(r2)
        // 没有对应按下的抬起放行
        let r3 = router.route(key: .volumeUp, isDown: false, isRepeat: false, modifiers: [])
        #expect(!r3)
    }

    @Test func `passed down passes its up`() {
        var router = MediaKeyRouter()
        router.filters = [.init(token: FilterToken(rawValue: 1), filter: Fixed(decision: .pass))]
        let r4 = router.route(key: .mute, isDown: true, isRepeat: false, modifiers: [])
        #expect(!r4)
        let r5 = router.route(key: .mute, isDown: false, isRepeat: false, modifiers: [])
        #expect(!r5)
    }

    @Test func `brightness key codes`() {
        #expect(MediaKeyRouter.brightnessKey(keyCode: 144) == .brightnessUp)
        #expect(MediaKeyRouter.brightnessKey(keyCode: 145) == .brightnessDown)
        #expect(MediaKeyRouter.brightnessKey(keyCode: 0) == nil)
    }

    @Test func `fast presses from one source are never deduplicated`() {
        var router = MediaKeyRouter()
        let counter = Counter()
        router.filters = [.init(token: FilterToken(rawValue: 1), filter: counter)]
        for index in 0 ..< 10 {
            // 鼠标滚轮绑的音量键：每 2 毫秒一个
            _ = router.route(key: .volumeDown, isDown: true, isRepeat: false, modifiers: [], time: UInt64(index) * 2_000_000)
            _ = router.route(key: .volumeDown, isDown: false, isRepeat: false, modifiers: [])
        }
        #expect(counter.count == 10)
    }

    @Test func `twin from the other source follows the first decision`() {
        var router = MediaKeyRouter()
        let counter = Counter()
        router.filters = [.init(token: FilterToken(rawValue: 1), filter: counter)]
        let first = router.route(
            key: .brightnessUp, isDown: true, isRepeat: false, modifiers: [], source: .keyCode, time: 1_000_000,
        )
        let twin = router.route(
            key: .brightnessUp, isDown: true, isRepeat: false, modifiers: [], source: .systemDefined, time: 3_000_000,
        )
        #expect(first && twin)
        #expect(counter.count == 1)
        // 隔得久的另一个来源是新的一次按下
        _ = router.route(
            key: .brightnessUp, isDown: true, isRepeat: false, modifiers: [], source: .keyCode, time: 100_000_000,
        )
        #expect(counter.count == 2)
    }

    private final class Counter: RealtimeMediaKeyFilter, @unchecked Sendable {
        var count = 0
        func process(_: MediaKeyEvent) -> FilterDecision {
            count += 1
            return .consume
        }
    }
}

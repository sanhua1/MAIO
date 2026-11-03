@testable import FeatureSwitcher
import MAIOKit
import Testing

struct SwitcherSessionTests {
    private func items(_ count: Int) -> [SwitcherItem] {
        (0 ..< count).map {
            SwitcherItem(
                id: .init(pid: Int32($0), windowID: UInt32($0)), appName: "App\($0)", bundleID: nil,
                title: "W\($0)", isMinimized: false, isHidden: false,
            )
        }
    }

    private let optTab = KeyChord(string: "opt+tab")!
    private func key(_ chord: String, _ kind: KeyEvent.Kind = .down) -> KeyEvent {
        let parsed = KeyChord(string: chord)!
        return KeyEvent(kind: kind, keyCode: parsed.keyCode, modifiers: parsed.modifiers)
    }

    @Test func `starts on the previous window`() {
        #expect(SwitcherSession(items: items(4), trigger: optTab, reverse: false).selectedIndex == 1)
        #expect(SwitcherSession(items: items(4), trigger: optTab, reverse: true).selectedIndex == 3)
        #expect(SwitcherSession(items: items(1), trigger: optTab, reverse: false).selectedIndex == 0)
    }

    @Test func `tab cycles forward and shift tab backward with wrap around`() {
        var session = SwitcherSession(items: items(3), trigger: optTab, reverse: false)
        _ = session.handle(key("opt+tab"))
        #expect(session.selectedIndex == 2)
        _ = session.handle(key("opt+tab"))
        #expect(session.selectedIndex == 0)
        _ = session.handle(key("opt+shift+tab"))
        #expect(session.selectedIndex == 2)
        _ = session.handle(key("opt+left"))
        #expect(session.selectedIndex == 1)
    }

    @Test func `custom trigger key also cycles`() throws {
        let cmdGrave = try #require(KeyChord(string: "cmd+`"))
        var session = SwitcherSession(items: items(3), trigger: cmdGrave, reverse: false)
        _ = session.handle(key("cmd+`"))
        #expect(session.selectedIndex == 2)
    }

    @Test func `releasing the held modifier confirms`() {
        var session = SwitcherSession(items: items(3), trigger: optTab, reverse: false)
        #expect(session.handle(KeyEvent(kind: .flagsChanged, keyCode: 58, modifiers: [.option, .shift])) == .none)
        #expect(session.handle(KeyEvent(kind: .flagsChanged, keyCode: 58, modifiers: [])) == .confirm)
    }

    @Test func `cmd tab trigger waits for command release`() throws {
        var session = try SwitcherSession(items: items(3), trigger: #require(KeyChord(string: "cmd+tab")), reverse: false)
        #expect(session.handle(KeyEvent(kind: .flagsChanged, keyCode: 55, modifiers: [.command])) == .none)
        #expect(session.handle(KeyEvent(kind: .flagsChanged, keyCode: 55, modifiers: [.option])) == .confirm)
    }

    @Test func `quick release before session started`() {
        let session = SwitcherSession(items: items(3), trigger: optTab, reverse: false)
        #expect(session.isReleased(currentModifiers: []))
        #expect(!session.isReleased(currentModifiers: [.option]))
    }

    @Test func `escape cancels, return confirms, window actions target selection`() {
        var session = SwitcherSession(items: items(3), trigger: optTab, reverse: false)
        #expect(session.handle(key("opt+escape")) == .cancel)
        #expect(session.handle(key("opt+return")) == .confirm)
        #expect(session.handle(key("opt+w")) == .closeWindow(items(3)[1]))
        #expect(session.handle(key("opt+q")) == .quitApp(items(3)[1]))
    }

    @Test func `removing items keeps selection in range`() {
        var session = SwitcherSession(items: items(2), trigger: optTab, reverse: false)
        session.remove { $0.pid == 1 }
        #expect(session.selectedIndex == 0)
        #expect(session.items.count == 1)
    }
}

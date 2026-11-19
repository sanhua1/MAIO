import Foundation
@testable import MAIOCore
import MAIOKit
import Testing

/// 远程桌面 App 在前台时让出快捷键和按键过滤器（ADR-0027）
struct RemoteDesktopRoutingTests {
    private let remote = "com.netease.uuremote"

    private func key(_ chord: String, _ kind: KeyEvent.Kind = .down) -> KeyEvent {
        let parsed = KeyChord(string: chord)!
        return KeyEvent(kind: kind, keyCode: parsed.keyCode, modifiers: parsed.modifiers)
    }

    private func router(frontmost: String?) throws -> KeyboardRouter {
        var router = KeyboardRouter()
        let binding = try CommandBinding(
            id: "b",
            trigger: .hotkey(#require(KeyChord(string: "opt+tab"))),
            command: "system.openApp",
        )
        router.table = HotkeyTable(bindings: [binding]) { _ in true }
        router.filters = [KeyFilterEntry(token: FilterToken(rawValue: 1), filter: SwallowFilter())]
        router.passthroughApps = [remote]
        router.frontmost = frontmost
        return router
    }

    @Test func `remote desktop in front gets every key`() throws {
        var router = try router(frontmost: remote)
        #expect(router.route(key("opt+tab")) == .pass)
        #expect(router.route(key("opt+tab", .up)) == .pass)
        #expect(router.route(key("x")) == .pass)
    }

    @Test func `other apps still use bindings and filters`() throws {
        var router = try router(frontmost: "com.apple.Safari")
        #expect(router.route(key("x")) == .swallow)
        guard case .fire = router.route(key("opt+tab")).effect else {
            Issue.record("⌥Tab 应该触发绑定")
            return
        }
    }

    @Test func `key swallowed before switching still swallows its key up`() throws {
        var router = try router(frontmost: "com.apple.Safari")
        #expect(router.route(key("x")) == .swallow)
        router.frontmost = remote
        #expect(router.route(key("x", .up)) == .swallow)
    }

    @Test func `sessions keep their keys`() throws {
        var router = try router(frontmost: remote)
        router.hasSession = true
        #expect(router.route(key("tab")) == .init(consume: true, effect: .toSession(key("tab"))))
    }
}

/// 吞掉 x
private struct SwallowFilter: RealtimeKeyFilter {
    func process(_ event: KeyEvent, _: RealtimeEnvironment) -> KeyFilterDecision {
        event.keyCode == KeyChord(string: "x")?.keyCode ? .consume : .pass
    }
}

@MainActor
struct RemoteDesktopModeTests {
    private func makeConfig() -> ConfigStore {
        ConfigStore(root: FileManager.default.temporaryDirectory.appending(path: "maio-rd-\(UUID().uuidString)"))
    }

    @Test func `defaults on with UU remote`() {
        let mode = RemoteDesktopMode(config: makeConfig(), input: InputEngine { _ in })
        #expect(mode.settings.enabled)
        #expect(mode.settings.bundleIDs.contains("com.netease.uuremote"))
    }

    @Test func `tracks front app and persists changes`() {
        let config = makeConfig()
        let mode = RemoteDesktopMode(config: config, input: InputEngine { _ in })
        mode.updateFrontmost("com.netease.uuremote")
        #expect(mode.isActive)
        mode.setEnabled(false)
        #expect(!mode.isActive)
        mode.setEnabled(true)
        mode.add(" com.example.vm ")
        mode.add("com.example.vm")
        mode.remove("com.netease.uuremote")
        #expect(!mode.isActive)
        let reloaded = RemoteDesktopMode(config: config, input: InputEngine { _ in })
        #expect(reloaded.settings.bundleIDs.filter { $0 == "com.example.vm" }.count == 1)
        #expect(!reloaded.settings.bundleIDs.contains("com.netease.uuremote"))
        reloaded.restoreDefaults()
        #expect(reloaded.settings.bundleIDs == RemoteDesktopSettings.defaultBundleIDs)
    }
}

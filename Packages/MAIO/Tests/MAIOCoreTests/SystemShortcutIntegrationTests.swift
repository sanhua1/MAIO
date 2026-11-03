import Foundation
@testable import MAIOCore
import MAIOKit
import Testing

/// 真实修改系统快捷键的集成测试，会暂时禁用再恢复 🌐A（编号 210）。
/// 默认跳过；手动运行：`MAIO_SYSTEM_TESTS=1 swift test --package-path Packages/MAIO --filter SystemShortcutIntegration`
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MAIO_SYSTEM_TESTS"] == "1"))
struct SystemShortcutIntegrationTests {
    static let dockID = 210

    @Test func `disable and restore round trip on real system`() throws {
        let store = MacSystemShortcutStore()
        try #require(store.isAvailable)
        let config = ConfigStore(root: FileManager.default.temporaryDirectory.appending(path: "maio-it-\(UUID().uuidString)"))
        let manager = SystemShortcutManager(store: store, config: config)
        let before = store.preferenceEntry(for: Self.dockID)
        let wasEnabled = try #require(manager.shortcuts.first { $0.id == Self.dockID }).isEnabled
        try #require(wasEnabled, "测试前提：🌐A 处于启用状态")

        manager.disable([Self.dockID], reason: "集成测试")
        #expect(store.preferenceEntry(for: Self.dockID)?.objectValue?["enabled"] == .bool(false))
        #expect(manager.conflicts(for: KeyChord(keyCode: 0, modifiers: .function)).isEmpty)
        print("[集成测试] 已禁用 210：", store.preferenceEntry(for: Self.dockID) ?? "nil")

        manager.restore(Self.dockID)
        #expect(store.preferenceEntry(for: Self.dockID) == before)
        #expect(manager.conflicts(for: KeyChord(keyCode: 0, modifiers: .function)).map(\.id) == [Self.dockID])
        print("[集成测试] 已恢复 210：", store.preferenceEntry(for: Self.dockID) ?? "nil（使用系统默认值）")
    }
}

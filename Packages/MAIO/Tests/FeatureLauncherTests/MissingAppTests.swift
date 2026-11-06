@testable import FeatureLauncher
import Foundation
import Testing

/// 卸载了的应用（应用列表还没重扫）打开面板时就拿掉，不会搜到了点了没反应
@MainActor
struct MissingAppTests {
    @Test func `deleted apps disappear when the panel opens`() {
        let model = LauncherViewModel()
        let finder = LauncherItem.app(
            path: "/System/Library/CoreServices/Finder.app", bundleID: "com.apple.finder",
            title: "Finder", subtitle: "/System/Library/CoreServices/", names: ["Finder"],
        )
        let gone = LauncherItem.app(
            path: "/Applications/MAIO-已经卸载-\(UUID().uuidString).app", bundleID: "org.example.gone",
            title: "Gone", subtitle: "/Applications/", names: ["Gone"],
        )
        model.apps = [finder, gone]
        model.prepareForOpen(keepQuery: false, running: [])
        #expect(model.apps.map(\.id) == [finder.id])
    }
}

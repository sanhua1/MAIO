@testable import FeatureSwitcher
import Testing

struct WindowOrderingTests {
    private let sample: [WindowRecord] = [
        .init(pid: 3, appName: "c", bundleID: "c", windowID: 30, title: "c", isMinimized: true, isAppHidden: false, zIndex: nil),
        .init(pid: 1, appName: "a", bundleID: "a", windowID: 11, title: "a2", isMinimized: false, isAppHidden: false, zIndex: 2),
        .init(pid: 2, appName: "b", bundleID: "b", windowID: 20, title: "b", isMinimized: false, isAppHidden: false, zIndex: 1),
        .init(pid: 1, appName: "a", bundleID: "a", windowID: 10, title: "a1", isMinimized: false, isAppHidden: false, zIndex: 0),
        .init(pid: 4, appName: "d", bundleID: "d", windowID: nil, title: "", isMinimized: false, isAppHidden: false, zIndex: nil),
        .init(pid: 5, appName: "e", bundleID: "e", windowID: 50, title: "e", isMinimized: false, isAppHidden: true, zIndex: nil),
    ]

    @Test func `on screen windows by z order then others by app recency`() {
        let items = WindowOrdering.items(from: sample, appRecency: ["e", "c"], settings: .defaultValue)
        #expect(items.map(\.windowID) == [10, 20, 11, 50, 30])
    }

    @Test func `filters follow settings`() {
        var settings = SwitcherSettings.defaultValue
        settings.showMinimizedWindows = false
        settings.showHiddenApps = false
        settings.showAppsWithoutWindows = true
        settings.excludedBundleIDs = ["b"]
        let items = WindowOrdering.items(from: sample, appRecency: [], settings: settings)
        #expect(items.map(\.pid) == [1, 1, 4])
    }

    @Test func `one item per app keeps the most recent window`() {
        var settings = SwitcherSettings.defaultValue
        settings.oneItemPerApp = true
        let items = WindowOrdering.items(from: sample, appRecency: ["e", "c"], settings: settings)
        #expect(items.map(\.pid) == [1, 2, 5, 3])
        #expect(items.first?.windowID == 10)
        #expect(items.first?.displayTitle == "a")
    }
}

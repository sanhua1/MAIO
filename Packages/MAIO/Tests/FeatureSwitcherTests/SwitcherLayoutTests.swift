@testable import FeatureSwitcher
import MAIOKit
import Testing

struct SwitcherLayoutTests {
    @Test(arguments: [(1, 1), (2, 2), (3, 3), (4, 2), (5, 3), (6, 3), (9, 3), (10, 4), (16, 4), (17, 5)])
    func `rectangular columns`(count: Int, expected: Int) {
        #expect(SwitcherLayout.columns(count: count, maxColumns: 10) == expected)
    }

    @Test func `limited by screen width`() {
        #expect(SwitcherLayout.columns(count: 30, maxColumns: 4) == 4)
    }

    /// 5 项、3 列：
    /// 0 1 2
    /// 3 4
    @Test func `vertical moves wrap within the column`() {
        #expect(SwitcherLayout.below(0, columns: 3, count: 5) == 3)
        #expect(SwitcherLayout.below(3, columns: 3, count: 5) == 0)
        #expect(SwitcherLayout.below(2, columns: 3, count: 5) == 2, "下一行这一列没有项，回到第一行")
        #expect(SwitcherLayout.above(0, columns: 3, count: 5) == 3)
        #expect(SwitcherLayout.above(2, columns: 3, count: 5) == 2, "这一列只有一项")
        #expect(SwitcherLayout.above(4, columns: 3, count: 5) == 1)
    }

    @Test func `session arrow keys use the grid`() throws {
        let items = (0 ..< 4).map {
            SwitcherItem(
                id: .init(pid: Int32($0), windowID: UInt32($0)), appName: "A", bundleID: nil,
                title: "", isMinimized: false, isHidden: false,
            )
        }
        var session = try SwitcherSession(items: items, trigger: #require(KeyChord(string: "opt+tab")), reverse: false)
        session.columns = 2
        #expect(session.selectedIndex == 1)
        _ = session.handle(KeyEvent(kind: .down, keyCode: 125, modifiers: .option))
        #expect(session.selectedIndex == 3)
        _ = session.handle(KeyEvent(kind: .down, keyCode: 123, modifiers: .option))
        #expect(session.selectedIndex == 2)
        _ = session.handle(KeyEvent(kind: .down, keyCode: 126, modifiers: .option))
        #expect(session.selectedIndex == 0)
    }
}

struct SwitcherGridRowsTests {
    private func items(_ count: Int) -> [SwitcherItem] {
        (0 ..< count).map {
            SwitcherItem(
                id: .init(pid: Int32($0), windowID: UInt32($0)), appName: "A", bundleID: nil,
                title: "", isMinimized: false, isHidden: false,
            )
        }
    }

    @Test func `rows carry the items themselves`() {
        let rows = SwitcherLayout.rows(items: items(5), columns: 3)
        #expect(rows.map { $0.slots.map(\.index) } == [[0, 1, 2], [3, 4]])
        #expect(rows[1].slots[1].item.windowID == 4)
    }

    @Test func `fewer items than columns and empty list are safe`() {
        #expect(SwitcherLayout.rows(items: items(2), columns: 4).map(\.slots.count) == [2])
        #expect(SwitcherLayout.rows(items: [], columns: 3).isEmpty)
        #expect(SwitcherLayout.rows(items: items(3), columns: 0).map(\.slots.count) == [1, 1, 1])
    }
}

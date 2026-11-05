@testable import FeatureScreenshot
import Testing

@MainActor
struct ToolbarHoverTests {
    @Test func `hover takes the last entered control`() {
        let model = ToolbarModel()
        model.setOverToolbar(true)
        let first = ToolbarHint(help: "撤销（⌘Z）")
        let second = ToolbarHint(help: "大小", cursor: .iBeam)
        model.setHover(first, inside: true)
        #expect(model.hint == first)
        model.setHover(second, inside: true)
        #expect(model.hint == second)
        // 相邻控件之间先进入后退出时，不能退回上一个
        model.setHover(first, inside: false)
        #expect(model.hint == second)
        model.setHover(second, inside: false)
        #expect(model.hint == nil)
    }

    @Test func `leaving the toolbar clears stale hints`() {
        let model = ToolbarModel()
        model.setOverToolbar(true)
        model.setHover(ToolbarHint(help: "贴图"), inside: true)
        #expect(model.hint != nil)
        model.setOverToolbar(false)
        #expect(model.hint == nil)
        #expect(model.overToolbar == false)
    }

    @Test func `clear hover resets everything`() {
        let model = ToolbarModel()
        model.setOverToolbar(true)
        model.setHover(ToolbarHint(help: "保存"), inside: true)
        model.clearHover()
        #expect(model.hint == nil)
        #expect(model.overToolbar == false)
        // 清空后同一个控件再次进入还能正常显示
        model.setOverToolbar(true)
        model.setHover(ToolbarHint(help: "保存"), inside: true)
        #expect(model.hint == ToolbarHint(help: "保存"))
    }
}

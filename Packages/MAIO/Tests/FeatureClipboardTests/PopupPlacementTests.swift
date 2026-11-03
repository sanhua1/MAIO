import CoreGraphics
@testable import FeatureClipboard
import Testing

struct PopupPlacementTests {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 400, height: 300)

    @Test func `below the caret line, aligned with caret`() {
        let caret = CGRect(x: 200, y: 500, width: 0, height: 18)
        let point = PopupPlacement.topLeft(around: caret, size: size, in: visible)
        #expect(point == CGPoint(x: 188, y: 494))
    }

    @Test func `above the line when no room below, without covering it`() {
        let caret = CGRect(x: 200, y: 100, width: 0, height: 18)
        let point = PopupPlacement.topLeft(around: caret, size: size, in: visible)
        // 面板底边在这一行上方
        #expect(point.y - size.height >= caret.maxY)
    }

    @Test func `kept inside the screen horizontally`() {
        let caret = CGRect(x: 980, y: 500, width: 0, height: 18)
        let point = PopupPlacement.topLeft(around: caret, size: size, in: visible)
        #expect(point.x + size.width <= visible.maxX)
    }
}

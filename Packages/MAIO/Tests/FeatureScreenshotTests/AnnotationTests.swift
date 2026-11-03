import CoreGraphics
@testable import FeatureScreenshot
import Foundation
import Testing

struct AnnotationGeometryTests {
    func make(_ shape: AnnotationShape, width: CGFloat = 4) -> Annotation {
        Annotation(shape: shape, color: .red, lineWidth: width)
    }

    @Test func `hollow rectangle is hit only near its edges`() {
        let rect = make(.rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), filled: false, rounded: false))
        #expect(rect.contains(CGPoint(x: 1, y: 50)))
        #expect(!rect.contains(CGPoint(x: 50, y: 50)))
        let filled = make(.rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), filled: true, rounded: false))
        #expect(filled.contains(CGPoint(x: 50, y: 50)))
    }

    @Test func `ellipse and line hit tests`() {
        let ellipse = make(.ellipse(CGRect(x: 0, y: 0, width: 200, height: 100), filled: false))
        #expect(ellipse.contains(CGPoint(x: 100, y: 1)))
        #expect(!ellipse.contains(CGPoint(x: 100, y: 50)))
        #expect(!ellipse.contains(CGPoint(x: 2, y: 2)))
        let line = make(.line(from: .zero, to: CGPoint(x: 100, y: 100), dashed: false))
        #expect(line.contains(CGPoint(x: 52, y: 48)))
        #expect(!line.contains(CGPoint(x: 80, y: 20)))
        let pen = make(.pen([.zero, CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)]))
        #expect(pen.contains(CGPoint(x: 51, y: 25)))
    }

    @Test func `move keeps id and resize uses handles`() {
        let rect = make(.rectangle(CGRect(x: 10, y: 10, width: 20, height: 20), filled: false, rounded: false))
        let moved = rect.moved(by: CGVector(dx: 5, dy: -5))
        #expect(moved.id == rect.id)
        #expect(moved.shape == .rectangle(CGRect(x: 15, y: 5, width: 20, height: 20), filled: false, rounded: false))
        let resized = rect.resized(.frame(.bottomRight), to: CGPoint(x: 50, y: 60))
        #expect(resized.shape == .rectangle(CGRect(x: 10, y: 10, width: 40, height: 50), filled: false, rounded: false))
        let arrow = make(.arrow(from: .zero, to: CGPoint(x: 10, y: 0)))
        #expect(arrow.handle(at: CGPoint(x: 11, y: 1)) == .end)
        #expect(arrow.resized(.end, to: CGPoint(x: 0, y: 30)).shape == .arrow(from: .zero, to: CGPoint(x: 0, y: 30)))
    }

    @Test func `transform converts to image coordinates`() {
        let counter = make(.counter(center: CGPoint(x: 110, y: 220), number: 3, radius: 10))
        let local = counter.transformed(offset: CGVector(dx: -100, dy: -200), scale: 2)
        #expect(local.shape == .counter(center: CGPoint(x: 20, y: 40), number: 3, radius: 20))
        #expect(local.lineWidth == 8)
    }

    @Test func `shift snapping`() {
        let snapped = Snapping.angle(from: .zero, to: CGPoint(x: 100, y: 10))
        #expect(abs(snapped.y) < 0.001)
        #expect(abs(snapped.x - hypot(100, 10)) < 0.001)
        let diagonal = Snapping.angle(from: .zero, to: CGPoint(x: 100, y: 90))
        #expect(abs(diagonal.x - diagonal.y) < 0.001)
        #expect(Snapping.square(from: .zero, to: CGPoint(x: -30, y: 10)) == CGPoint(x: -30, y: 30))
    }

    @Test func `annotations round-trip through JSON`() throws {
        let items = [
            make(.text(TextBox(origin: .zero, string: "你好", fontSize: 18, bold: true, decoration: .outline))),
            make(.mosaic(CGRect(x: 1, y: 2, width: 3, height: 4), blockSize: 8)),
            make(.highlighter([.zero, CGPoint(x: 5, y: 5)])),
        ]
        let decoded = try JSONDecoder().decode([Annotation].self, from: JSONEncoder().encode(items))
        #expect(decoded == items)
    }
}

struct AnnotationDocumentTests {
    func rect(_ x: CGFloat) -> Annotation {
        Annotation(
            shape: .rectangle(CGRect(x: x, y: 0, width: 10, height: 10), filled: true, rounded: false),
            color: .red,
            lineWidth: 2,
        )
    }

    @Test func `undo and redo restore snapshots`() {
        var document = AnnotationDocument()
        document.add(rect(0))
        document.add(rect(20))
        #expect(document.items.count == 2)
        document.undo()
        #expect(document.items.count == 1)
        document.redo()
        #expect(document.items.count == 2)
        document.undo()
        document.add(rect(40))
        #expect(!document.canRedo)
    }

    @Test func `undo is limited to 100 steps`() {
        var document = AnnotationDocument()
        for index in 0 ..< 120 {
            document.add(rect(CGFloat(index)))
        }
        for _ in 0 ..< 200 {
            document.undo()
        }
        #expect(document.items.count == 20)
    }

    @Test func `continuous size changes are one undo step`() {
        var editor = AnnotationEditor()
        editor.select(tool: .pen)
        _ = editor.mouseDown(at: .zero, clickCount: 1, selection: CGRect(x: 0, y: 0, width: 100, height: 100))
        editor.mouseDragged(to: CGPoint(x: 50, y: 50), constrained: false)
        editor.mouseUp()
        for value in stride(from: 5.0, through: 20, by: 1) {
            editor.setSize(value)
        }
        #expect(editor.document.items.first?.lineWidth == 20)
        editor.document.undo()
        #expect(editor.document.items.first?.lineWidth == 4)
        editor.setSize(500)
        #expect(editor.document.items.first?.lineWidth == 40)
    }

    @Test func `undo clears selection of removed item`() {
        var document = AnnotationDocument()
        let item = rect(0)
        document.add(item)
        document.selectedID = item.id
        document.undo()
        #expect(document.selectedID == nil)
    }

    @Test func `hit returns the topmost item`() {
        var document = AnnotationDocument()
        let bottom = rect(0)
        let top = rect(5)
        document.add(bottom)
        document.add(top)
        #expect(document.hit(at: CGPoint(x: 7, y: 5))?.id == top.id)
    }
}

struct AnnotationEditorTests {
    let selection = CGRect(x: 0, y: 0, width: 500, height: 500)

    @Test func `drawing a rectangle adds and selects it`() {
        var editor = AnnotationEditor()
        editor.select(tool: .rectangle)
        do {
            let outcome = editor.mouseDown(at: CGPoint(x: 10, y: 10), clickCount: 1, selection: selection)
            #expect(outcome == .handled)
        }
        editor.mouseDragged(to: CGPoint(x: 60, y: 30), constrained: true)
        #expect(editor.draft != nil)
        editor.mouseUp()
        #expect(editor.document.items.count == 1)
        #expect(editor.document.selectedID == editor.document.items.first?.id)
        if case let .rectangle(frame, _, _) = editor.document.items.first?.shape {
            #expect(frame == CGRect(x: 10, y: 10, width: 50, height: 50))
        } else {
            Issue.record("不是矩形")
        }
    }

    @Test func `tiny drags are discarded`() {
        var editor = AnnotationEditor()
        editor.select(tool: .arrow)
        _ = editor.mouseDown(at: CGPoint(x: 10, y: 10), clickCount: 1, selection: selection)
        editor.mouseDragged(to: CGPoint(x: 11, y: 10), constrained: false)
        editor.mouseUp()
        #expect(editor.document.isEmpty)
    }

    @Test func `clicking outside selection with a tool is not handled`() {
        var editor = AnnotationEditor()
        editor.select(tool: .pen)
        do {
            let outcome = editor.mouseDown(at: CGPoint(x: 600, y: 10), clickCount: 1, selection: selection)
            #expect(outcome == .notHandled)
        }
    }

    @Test func `without a tool click selects and drags move`() {
        var editor = AnnotationEditor()
        editor.select(tool: .ellipse)
        _ = editor.mouseDown(at: CGPoint(x: 100, y: 100), clickCount: 1, selection: selection)
        editor.mouseDragged(to: CGPoint(x: 200, y: 200), constrained: false)
        editor.mouseUp()
        editor.select(tool: .ellipse) // 再选一次 = 取消工具
        #expect(editor.tool == nil)
        do {
            let outcome = editor.mouseDown(at: CGPoint(x: 400, y: 400), clickCount: 1, selection: selection)
            #expect(outcome == .notHandled)
        }
        #expect(editor.document.selectedID == nil)
        do {
            let outcome = editor.mouseDown(at: CGPoint(x: 150, y: 101), clickCount: 1, selection: selection)
            #expect(outcome == .handled)
        }
        editor.mouseDragged(to: CGPoint(x: 160, y: 111), constrained: false)
        editor.mouseUp()
        #expect(editor.document.items.first?.bounds.minX == 108)
        editor.document.undo()
        #expect(editor.document.items.first?.bounds.minX == 98)
    }

    @Test func `counters increment and wheel adjusts`() {
        var editor = AnnotationEditor()
        editor.select(tool: .counter)
        _ = editor.mouseDown(at: CGPoint(x: 10, y: 10), clickCount: 1, selection: selection)
        editor.mouseUp()
        editor.document.selectedID = nil
        _ = editor.mouseDown(at: CGPoint(x: 50, y: 10), clickCount: 1, selection: selection)
        editor.mouseUp()
        #expect(editor.document.nextCounterNumber == 3)
        editor.adjustCounter(by: 5)
        #expect(editor.document.nextCounterNumber == 8)
        editor.adjustCounter(by: -100)
        #expect(editor.document.nextCounterNumber == 1)
    }

    @Test func `style changes apply to the selected annotation`() {
        var editor = AnnotationEditor()
        editor.select(tool: .line)
        _ = editor.mouseDown(at: .zero, clickCount: 1, selection: selection)
        editor.mouseDragged(to: CGPoint(x: 100, y: 0), constrained: false)
        editor.mouseUp()
        editor.setColor(.blue)
        editor.setSize(10)
        editor.setOptions { $0.dashed = true }
        let line = editor.document.items.first
        #expect(line?.color == .blue)
        #expect(line?.lineWidth == 10)
        #expect(line?.shape == .line(from: .zero, to: CGPoint(x: 100, y: 0), dashed: true))
        #expect(editor.style.color == .blue)
        // 撤销一次只撤销最后一个修改
        editor.document.undo()
        #expect(editor.document.items.first?.lineWidth == 10)
        #expect(editor.document.items.first?.shape == .line(from: .zero, to: CGPoint(x: 100, y: 0), dashed: false))
    }

    @Test func `text tool begins and commits text`() {
        var editor = AnnotationEditor()
        editor.select(tool: .text)
        do {
            let outcome = editor.mouseDown(at: CGPoint(x: 5, y: 5), clickCount: 1, selection: selection)
            #expect(outcome == .beginText(CGPoint(x: 5, y: 5)))
        }
        var box = editor.newTextBox(at: CGPoint(x: 5, y: 5))
        box.string = "标注"
        box.size = CGSize(width: 50, height: 24)
        editor.commitText(box, color: .red, editing: nil)
        let id = try? #require(editor.document.items.first?.id)
        do {
            let outcome = editor.mouseDown(at: CGPoint(x: 20, y: 10), clickCount: 1, selection: selection)
            #expect(outcome == .editText(id ?? UUID()))
        }
        box.string = ""
        editor.commitText(box, color: .red, editing: id)
        #expect(editor.document.isEmpty)
    }

    func measure(_: TextBox) -> CGSize {
        CGSize(width: 30, height: 20)
    }

    @Test func `committed text is selected and palette edits it`() {
        var editor = AnnotationEditor()
        editor.select(tool: .text)
        var box = editor.newTextBox(at: .zero)
        box.string = "字"
        editor.commitText(box, color: .red, editing: nil)
        #expect(editor.selectedText != nil)
        // 外观为"无"：即使选了"背景"，色板也改文字颜色
        editor.textColorTarget = .background
        editor.changeText(.color(.blue), measure: measure)
        #expect(editor.document.items.first?.color == .blue)
        // 改成底色后，色板改底色，文字颜色不变
        editor.changeText(.decoration(.background), measure: measure)
        editor.changeText(.color(.yellow), measure: measure)
        let (annotation, updated) = (editor.selectedText?.annotation, editor.selectedText?.box)
        #expect(updated?.decoration == .background)
        #expect(updated?.backgroundColor == .yellow)
        #expect(annotation?.color == .blue)
        // 粗体切换的是这段文字自己的值，并记成默认样式
        editor.changeText(.toggleBold, measure: measure)
        #expect(editor.selectedText?.box.bold == true)
        #expect(editor.style.bold)
        #expect(editor.style.textBackgroundColor == .yellow)
        #expect(editor.style.textDecoration == .background)
        // 一次修改一步撤销
        editor.document.undo()
        #expect(editor.selectedText?.box.bold == false)
    }

    @Test func `without selection text changes update defaults`() {
        var editor = AnnotationEditor()
        editor.select(tool: .text)
        editor.changeText(.decoration(.outline), measure: measure)
        editor.textColorTarget = .background
        editor.changeText(.color(.black), measure: measure)
        editor.changeText(.fontSize(36), measure: measure)
        let box = editor.newTextBox(at: .zero)
        #expect(box.decoration == .outline)
        #expect(box.backgroundColor == .black)
        #expect(box.fontSize == 36)
        #expect(editor.document.isEmpty)
    }

    @Test func `old text without background color gets the automatic one`() {
        let box = TextBox(origin: .zero, string: "a", fontSize: 14, bold: false, decoration: .outline)
        #expect(TextAppearance(box: box, color: .red).background == .white)
        #expect(TextAppearance(box: box, color: .yellow).background == .black)
    }

    @Test func `escape deselects then drops the tool`() {
        var editor = AnnotationEditor()
        editor.select(tool: .rectangle)
        _ = editor.mouseDown(at: .zero, clickCount: 1, selection: selection)
        editor.mouseDragged(to: CGPoint(x: 50, y: 50), constrained: false)
        editor.mouseUp()
        let first = editor.escape()
        #expect(first)
        #expect(editor.document.selectedID == nil)
        let second = editor.escape()
        #expect(second)
        #expect(editor.tool == nil)
        let third = editor.escape()
        #expect(!third)
    }
}

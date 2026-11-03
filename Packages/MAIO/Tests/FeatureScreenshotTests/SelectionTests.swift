import CoreGraphics
@testable import FeatureScreenshot
import Testing

struct SelectionGeometryTests {
    let rect = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func `finds handles within tolerance`() {
        #expect(SelectionGeometry.handle(at: CGPoint(x: 103, y: 98), in: rect) == .topLeft)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 200, y: 200), in: rect) == .bottom)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 150, y: 150), in: rect) == nil)
    }

    @Test func `small selection only has corner handles`() {
        let small = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(SelectionGeometry.handle(at: CGPoint(x: 5, y: 0), in: small) == .topLeft)
    }

    @Test func `resizing past the opposite edge flips`() {
        let resized = SelectionGeometry.resize(rect, handle: .left, to: CGPoint(x: 350, y: 0))
        #expect(resized == CGRect(x: 300, y: 100, width: 50, height: 100))
        let corner = SelectionGeometry.resize(rect, handle: .bottomRight, to: CGPoint(x: 320, y: 250))
        #expect(corner == CGRect(x: 100, y: 100, width: 220, height: 150))
    }

    @Test func `moving stays inside bounds`() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let moved = SelectionGeometry.move(rect, by: CGVector(dx: 500, dy: -500), within: bounds)
        #expect(moved == CGRect(x: 200, y: 0, width: 200, height: 100))
    }

    @Test func `pixel rect is relative to display and scaled`() {
        let display = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let pixels = SelectionGeometry.pixelRect(
            of: CGRect(x: -1340, y: 10, width: 100, height: 50), displayBounds: display, scale: 2,
        )
        #expect(pixels == CGRect(x: 200, y: 20, width: 200, height: 100))
    }

    @Test func `aligns to physical pixels`() {
        let aligned = SelectionGeometry.pixelAligned(CGRect(x: 10.3, y: 10.6, width: 20.1, height: 5), scale: 2)
        #expect(aligned == CGRect(x: 10.5, y: 10.5, width: 20, height: 5))
    }
}

struct CaptureInteractionTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func `dragging creates a clamped selection`() {
        var interaction = CaptureInteraction()
        _ = interaction.mouseDown(at: CGPoint(x: 100, y: 100), clickCount: 1, displayBounds: screen)
        interaction.mouseDragged(to: CGPoint(x: 1200, y: 300))
        interaction.mouseUp(highlighted: nil)
        #expect(interaction.selection == CGRect(x: 100, y: 100, width: 900, height: 200))
        #expect(!interaction.isDragging)
    }

    @Test func `click selects the highlighted window`() {
        var interaction = CaptureInteraction()
        _ = interaction.mouseDown(at: CGPoint(x: 100, y: 100), clickCount: 1, displayBounds: screen)
        interaction.mouseDragged(to: CGPoint(x: 101, y: 101))
        interaction.mouseUp(highlighted: CGRect(x: 50, y: -20, width: 300, height: 200))
        #expect(interaction.selection == CGRect(x: 50, y: 0, width: 300, height: 180))
    }

    @Test func `click outside keeps the existing selection`() {
        var interaction = CaptureInteraction()
        interaction.select(CGRect(x: 10, y: 10, width: 50, height: 50), displayBounds: screen)
        _ = interaction.mouseDown(at: CGPoint(x: 500, y: 500), clickCount: 1, displayBounds: screen)
        interaction.mouseUp(highlighted: CGRect(x: 400, y: 400, width: 200, height: 200))
        #expect(interaction.selection == CGRect(x: 10, y: 10, width: 50, height: 50))
    }

    @Test func `dragging inside moves and handles resize`() {
        var interaction = CaptureInteraction()
        interaction.select(CGRect(x: 100, y: 100, width: 100, height: 100), displayBounds: screen)
        _ = interaction.mouseDown(at: CGPoint(x: 150, y: 150), clickCount: 1, displayBounds: screen)
        interaction.mouseDragged(to: CGPoint(x: 160, y: 140))
        interaction.mouseUp(highlighted: nil)
        #expect(interaction.selection == CGRect(x: 110, y: 90, width: 100, height: 100))
        _ = interaction.mouseDown(at: CGPoint(x: 210, y: 190), clickCount: 1, displayBounds: screen)
        interaction.mouseDragged(to: CGPoint(x: 260, y: 240))
        interaction.mouseUp(highlighted: nil)
        #expect(interaction.selection == CGRect(x: 110, y: 90, width: 150, height: 150))
    }

    @Test func `double click inside confirms`() {
        var interaction = CaptureInteraction()
        interaction.select(CGRect(x: 100, y: 100, width: 100, height: 100), displayBounds: screen)
        #expect(interaction.mouseDown(at: CGPoint(x: 150, y: 150), clickCount: 2, displayBounds: screen) == .confirm)
    }

    @Test func `cancel clears selection first then exits`() {
        var interaction = CaptureInteraction()
        interaction.select(CGRect(x: 100, y: 100, width: 100, height: 100), displayBounds: screen)
        #expect(interaction.cancel() == .none)
        #expect(interaction.selection == nil)
        #expect(interaction.cancel() == .exit)
    }

    @Test func `nudge moves or resizes`() {
        var interaction = CaptureInteraction()
        interaction.select(CGRect(x: 100, y: 100, width: 100, height: 100), displayBounds: screen)
        interaction.nudge(dx: 0.5, dy: 0, resize: false)
        #expect(interaction.selection == CGRect(x: 100.5, y: 100, width: 100, height: 100))
        interaction.nudge(dx: 0, dy: -0.5, resize: true)
        #expect(interaction.selection == CGRect(x: 100.5, y: 100, width: 100, height: 99.5))
    }
}

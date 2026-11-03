@testable import FeatureScroll
import MAIOKit
import Testing

struct ZoomPlannerTests {
    private let zoom = ZoomConfig(enabled: true, modifier: .command, speed: 1, reversed: false)
    private let command = RealtimeEnvironment(frontmostBundleID: nil, modifiers: [.command])

    private func wheel(pixels: Double, device: PointerDeviceKind = .wheel, synthetic: Bool = false) -> PointerEvent {
        PointerEvent(scrollY: pixels / 10, scrollX: 0, pixelY: pixels, device: device, isSynthetic: synthetic)
    }

    @Test func `command plus wheel zooms, forward zooms in after reversing`() {
        // 用户反转了纵向（系统开着自然滚动）：往前拨时原始值为负，算出来是放大
        let value = ZoomPlanner.magnification(wheel(pixels: -10), command, zoom, reverseVertical: true)
        #expect(value == 0.05)
        let plain = ZoomPlanner.magnification(wheel(pixels: 10), command, zoom, reverseVertical: false)
        #expect(plain == 0.05)
    }

    @Test func `reversed and speed apply`() {
        var config = zoom
        config.reversed = true
        config.speed = 2
        #expect(ZoomPlanner.magnification(wheel(pixels: 10), command, config, reverseVertical: false) == -0.1)
    }

    @Test func `no zoom without modifier, for trackpad, synthetic or when disabled`() {
        let none = RealtimeEnvironment(frontmostBundleID: nil, modifiers: [])
        #expect(ZoomPlanner.magnification(wheel(pixels: 10), none, zoom, reverseVertical: false) == nil)
        #expect(ZoomPlanner.magnification(wheel(pixels: 10, device: .trackpad), command, zoom, reverseVertical: false) == nil)
        #expect(ZoomPlanner.magnification(wheel(pixels: 10, synthetic: true), command, zoom, reverseVertical: false) == nil)
        var off = zoom
        off.enabled = false
        #expect(ZoomPlanner.magnification(wheel(pixels: 10), command, off, reverseVertical: false) == nil)
        var option = zoom
        option.modifier = .option
        #expect(ZoomPlanner.magnification(wheel(pixels: 10), command, option, reverseVertical: false) == nil)
    }

    @Test func `excluded apps keep their own modifier scroll`() {
        var config = zoom
        config.excludedBundleIDs = ["app.maio.MAIO"]
        let onPin = RealtimeEnvironment(frontmostBundleID: nil, targetBundleID: "app.maio.MAIO", modifiers: [.command])
        #expect(ZoomPlanner.magnification(wheel(pixels: 10), onPin, config, reverseVertical: false) == nil)
        let elsewhere = RealtimeEnvironment(
            frontmostBundleID: "app.maio.MAIO",
            targetBundleID: "com.apple.Preview",
            modifiers: [.command],
        )
        #expect(ZoomPlanner.magnification(wheel(pixels: 10), elsewhere, config, reverseVertical: false) == 0.05)
    }

    @Test func `horizontal only scroll is not zoom`() {
        let horizontal = PointerEvent(scrollY: 0, scrollX: 2, pixelY: 0, pixelX: 20, device: .wheel)
        #expect(ZoomPlanner.magnification(horizontal, command, zoom, reverseVertical: false) == nil)
    }

    @Test func `easer emits the whole amount over several frames`() {
        var easer = ZoomEaser()
        easer.add(0.05)
        var total = 0.0
        var frames = 0
        while let step = easer.next() {
            total += step
            frames += 1
        }
        #expect(abs(total - 0.05) < 1e-9)
        #expect(frames > 3)
        #expect(easer.next() == nil)
    }
}

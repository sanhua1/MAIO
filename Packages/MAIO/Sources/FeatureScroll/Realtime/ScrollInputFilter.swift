import MAIOKit
import Synchronization

/// 注册到输入引擎的实时过滤器：修饰键 + 滚轮变成捏合缩放；其余反转方向，并把需要平滑的位移交给动画器。
final class ScrollInputFilter: RealtimeInputFilter {
    private let config: Mutex<ScrollConfig>
    let animator: SmoothScrollAnimator
    let zoomer: PinchZoomer

    init(config: ScrollConfig, poster: any SyntheticEventPoster) {
        self.config = Mutex(config)
        animator = SmoothScrollAnimator(poster: poster, parameters: config.animation)
        zoomer = PinchZoomer(poster: poster)
    }

    /// 设置变化时由主线程调用，原子替换配置快照。
    func update(_ newConfig: ScrollConfig) {
        config.withLock { $0 = newConfig }
    }

    func process(_ event: inout PointerEvent, _ environment: RealtimeEnvironment) -> FilterDecision {
        let snapshot = config.withLock { $0 }
        let reverse = snapshot.rules(for: environment.effectiveBundleID).reverseVertical
        if let magnification = ZoomPlanner.magnification(event, environment, snapshot.zoom, reverseVertical: reverse) {
            zoomer.add(magnification, modifier: snapshot.zoom.modifier.modifiers)
            return .consume
        }
        let plan = ScrollPlanner.plan(event, environment, snapshot)
        if plan.hasSmoothing {
            animator.add(y: plan.smoothY, x: plan.smoothX, parameters: snapshot.animation)
        }
        if plan.consume {
            return .consume
        }
        event.scrollY = plan.passY
        event.scrollX = plan.passX
        return .pass
    }
}

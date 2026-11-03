import AppKit
import MAIOKit

/// 一次长截图（spec F10、4.6，ADR-0014）：用户自己用滚轮往下滚，MAIO 不发任何滚动事件。
/// 选区开一个视频流，每来一帧就和参照帧（最后一次接上的帧）比较，接上新露出的部分，右侧面板显示长条预览。
/// 对不上时参照帧不变：滚回去重新有重叠就能继续，不会拼错。往回滚不算错误，只是暂时不拼。
/// 结束：点完成、Esc / ⏎、高度达到 30000 px。
@MainActor
final class ScrollCaptureSession {
    static let maximumHeight = 30000
    /// 没有新帧时等多久再看
    static let idleWait: Duration = .milliseconds(10)

    let rect: CGRect
    let scale: CGFloat
    private let keyboard: any KeyboardSession
    private let model = ScrollCaptureModel()
    private let frame: ScrollCaptureFrame
    /// 第一帧也用同一个截图方式截（和冻结画面的颜色处理可能有细微差别，会让逐像素比较失败）
    private var builder: LongImageBuilder?
    private var reference: GrayFrame?
    private var loop: Task<Void, Never>?
    private var keys: Task<Void, Never>?
    private var finished = false
    private let completion: (CGImage?) -> Void

    init(rect: CGRect, scale: CGFloat, input: any InputService, completion: @escaping (CGImage?) -> Void) {
        self.rect = rect
        self.scale = scale
        keyboard = input.beginKeyboardSession()
        self.completion = completion
        frame = ScrollCaptureFrame(rect: rect, model: model)
        model.finish = { [weak self] in self?.finish() }
    }

    func start(display: DisplayInfo) {
        frame.show()
        keys = Task { [weak self, keyboard] in
            for await event in keyboard.events where event.kind == .down {
                // Esc、⏎ 结束（键盘会话期间按键都被吞掉，不会打到下面的 App）
                if event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 {
                    self?.finish()
                }
            }
        }
        loop = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await RegionStream.start(rect: rect, display: display, scale: scale)
                await run(source)
                await source.stop()
            } catch {
                model.warning = "截图失败：\(error.localizedDescription)"
            }
            finish()
        }
    }

    func cancel() {
        finished = true
        loop?.cancel()
        cleanUp()
    }

    // MARK: 循环

    private func run(_ source: RegionStream) async {
        while !finished, !Task.isCancelled {
            guard let image = source.take() else {
                try? await Task.sleep(for: Self.idleWait)
                continue
            }
            guard let reference, builder != nil else {
                builder = LongImageBuilder(first: image, previewWidth: Int(ScrollCaptureSidebar.width * 2))
                self.reference = await Task.detached { GrayFrame(image) }.value
                model.height = image.height
                model.preview = builder?.preview()
                continue
            }
            switch await Self.match(image, reference: reference) {
            case let .moved(match, gray):
                model.warning = nil
                builder?.append(image, shift: match.offset)
                self.reference = gray
                model.height = builder?.height ?? 0
                model.preview = builder?.preview()
                if model.height >= Self.maximumHeight {
                    return
                }
            case .unchanged, .backward:
                model.warning = nil
            case .unknown:
                model.warning = "没对上：滚得太快了。\n滚回上次停下的位置，再慢一点往下滚"
            }
        }
    }

    private enum FrameResult {
        case moved(ScrollMatch, GrayFrame)
        case unchanged
        /// 往回滚了（还在已经拼过的范围里）：暂时不拼，参照帧不变
        case backward
        case unknown
    }

    /// 在后台转灰度、算偏移。往下对不上时再看是不是往回滚了
    private nonisolated static func match(_ image: CGImage, reference: GrayFrame) async -> FrameResult {
        await Task.detached(priority: .userInitiated) {
            guard let gray = GrayFrame(image) else { return FrameResult.unknown }
            switch ScrollMatcher.match(previous: reference, current: gray) {
            case let .moved(match): return .moved(match, gray)
            case .unchanged: return .unchanged
            case .unknown:
                if case .moved = ScrollMatcher.match(previous: gray, current: reference) {
                    return .backward
                }
                return .unknown
            }
        }.value
    }

    // MARK: 结束

    private func finish() {
        guard !finished else { return }
        finished = true
        loop?.cancel()
        cleanUp()
        let builder = builder
        Task {
            let image = await Task.detached(priority: .userInitiated) { builder?.compose() }.value
            completion(image)
        }
    }

    private func cleanUp() {
        keys?.cancel()
        keyboard.end()
        frame.close()
    }
}

import Darwin
import Foundation
import MAIOUI

/// 后台给图片条目识别文字（剪贴板搜索能搜到图片里的字）。
/// 一次只识别一张，最近用过的先做；新复制的图片和升级前的旧图片都走这里。
@MainActor
final class ImageTextIndexer {
    private let store: ClipStore
    private let logger: (String) -> Void
    private var task: Task<Void, Never>?
    /// 正在识别时又有新图片进来：做完手上这轮再查一遍
    private var pending = false

    init(store: ClipStore, logger: @escaping (String) -> Void) {
        self.store = store
        self.logger = logger
    }

    /// 有新图片、或者刚打开开关时调用
    func start() {
        guard task == nil else {
            pending = true
            return
        }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        pending = false
    }

    private func run() async {
        var count = 0
        repeat {
            pending = false
            while !Task.isCancelled, let id = try? await store.nextImageWithoutText() {
                await recognize(id)
                count += 1
            }
        } while pending && !Task.isCancelled
        if count > 0 {
            logger("识别了 \(count) 张图片里的文字")
            // 识别时解码的大图、Vision 的中间数据释放后，malloc 默认留着不还给系统（实测补识别 145 张后多占约 170 MB）
            malloc_zone_pressure_relief(nil, 0)
        }
        task = nil
    }

    private func recognize(_ id: Int64) async {
        var text = ""
        if let image = await store.imageForRecognition(id) {
            do {
                text = try await TextRecognition.lines(in: image).map(\.text).joined(separator: "\n")
            } catch {
                logger("识别图片文字失败（条目 \(id)）：\(error.localizedDescription)")
            }
        }
        guard !Task.isCancelled else { return }
        // 写失败（数据库出错）时也不能卡在同一条上反复识别：停下，下次启动再试
        do {
            try await store.setImageText(text, for: id)
        } catch {
            logger("保存图片文字失败：\(error.localizedDescription)")
            task?.cancel()
        }
    }
}

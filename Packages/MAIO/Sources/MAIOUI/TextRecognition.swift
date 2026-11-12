import CoreGraphics
import Vision

/// 系统 Vision 离线识别图片里的文字（截图 ⌘O、剪贴板图片搜索共用）。
/// 精确模式、自动识别语言、语言校正；失败时用快速模式再试一次。
/// 实验（2026-11-03）：中英混排的 900×360 图约 0.6～0.7 秒，自动识别语言能正确识别中文。
public enum TextRecognition {
    /// 识别出的一行文字
    public struct Line: Sendable, Equatable {
        public var text: String
        /// 在图片里的位置：归一化坐标（0...1），左上角原点
        public var box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    public static func lines(in image: CGImage) async throws -> [Line] {
        do {
            return try await recognize(image, level: .accurate)
        } catch {
            return try await recognize(image, level: .fast)
        }
    }

    private static func recognize(_ image: CGImage, level: RecognizeTextRequest.RecognitionLevel) async throws -> [Line] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = level
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision 的归一化坐标是左下角原点，换成左上角原点
            let box = observation.boundingBox.cgRect
            return Line(text: text, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
    }
}

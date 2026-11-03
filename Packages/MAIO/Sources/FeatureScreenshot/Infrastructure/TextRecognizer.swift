import CoreGraphics
import Vision

/// 系统 Vision 离线识别文字（spec F7、4.5）：精确模式、自动识别语言、语言校正；失败时用快速模式再试一次。
/// 实验（2026-11-03）：中英混排的 900×360 图约 0.6～0.7 秒，自动识别语言能正确识别中文。
enum TextRecognizer {
    static func recognize(_ image: CGImage) async throws -> String {
        let lines: [RecognizedLine]
        do {
            lines = try await recognize(image, level: .accurate)
        } catch {
            lines = try await recognize(image, level: .fast)
        }
        return OCRLayout.text(from: lines)
    }

    private static func recognize(
        _ image: CGImage,
        level: RecognizeTextRequest.RecognitionLevel,
    ) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = level
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision 的归一化坐标是左下角原点，换成左上角原点
            let box = observation.boundingBox.cgRect
            return RecognizedLine(text: text, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
    }
}

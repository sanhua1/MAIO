import CoreGraphics
import MAIOUI

/// 识别截图里的文字（spec F7、4.5）：识别本身在 MAIOUI 的 `TextRecognition`（剪贴板也用），这里按版面拼成文字。
enum TextRecognizer {
    static func recognize(_ image: CGImage) async throws -> String {
        let lines = try await TextRecognition.lines(in: image).map { RecognizedLine(text: $0.text, box: $0.box) }
        return OCRLayout.text(from: lines)
    }
}

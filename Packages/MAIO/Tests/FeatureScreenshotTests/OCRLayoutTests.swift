import CoreGraphics
@testable import FeatureScreenshot
import Testing

struct OCRLayoutTests {
    private func line(
        _ text: String,
        x: CGFloat = 0.02,
        y: CGFloat,
        width: CGFloat = 0.5,
        height: CGFloat = 0.08,
    ) -> RecognizedLine {
        RecognizedLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func `orders lines top to bottom`() {
        let lines = [line("第二行", y: 0.12), line("第一行", y: 0.02)]
        #expect(OCRLayout.text(from: lines) == "第一行\n第二行")
    }

    @Test func `joins columns on the same row left to right`() {
        // 来自实验：左栏比右栏稍高一点，中心仍在同一行范围内
        let lines = [
            line("Right column text", x: 0.55, y: 0.427, width: 0.2, height: 0.083),
            line("左栏文字", x: 0.022, y: 0.432, width: 0.09, height: 0.07),
        ]
        #expect(OCRLayout.text(from: lines) == "左栏文字 Right column text")
    }

    @Test func `separates paragraphs by a blank line when the gap is large`() {
        let lines = [line("Title", y: 0.0), line("Body one", y: 0.3), line("Body two", y: 0.4)]
        #expect(OCRLayout.text(from: lines) == "Title\n\nBody one\nBody two")
    }

    @Test func `drops blank results and trims`() {
        let lines = [line("  hello ", y: 0.0), line("   ", y: 0.1)]
        #expect(OCRLayout.text(from: lines) == "hello")
    }

    @Test func `empty input gives empty text`() {
        #expect(OCRLayout.text(from: []).isEmpty)
    }

    @Test func `recognition actions do not copy the image`() {
        #expect(CaptureAction.ocr.recognizesText)
        #expect(CaptureAction.translate.recognizesText)
        #expect(!CaptureAction.copy.recognizesText)
    }
}

struct TextRecognizerTests {
    /// 真正调用 Vision：把文字渲染成图片再识别（离线，约 1 秒）
    @MainActor @Test func `recognizes rendered chinese and english`() async throws {
        let content = try #require(PasteboardImage.render(text: "截图识别文字\nHello MAIO 2026", scale: 2))
        let text = try await TextRecognizer.recognize(content.image)
        #expect(text.contains("截图识别文字"))
        #expect(text.contains("Hello MAIO"))
    }
}

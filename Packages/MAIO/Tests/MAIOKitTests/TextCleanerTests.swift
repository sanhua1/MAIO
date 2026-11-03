import MAIOKit
import Testing

struct TextCleanerTests {
    @Test func `joins english lines with space`() {
        #expect(TextCleaner.removingLineBreaks("The quick brown\nfox jumps") == "The quick brown fox jumps")
    }

    @Test func `joins chinese lines without space`() {
        #expect(TextCleaner.removingLineBreaks("今天天气\n很好") == "今天天气很好")
    }

    @Test func `keeps paragraphs`() {
        #expect(TextCleaner.removingLineBreaks("a\nb\n\n\nc\r\nd") == "a b\n\nc d")
    }

    @Test func `rejoins hyphenated words`() {
        #expect(TextCleaner.removingLineBreaks("trans-\nlation works") == "translation works")
        // 大写开头不是断词（例如 "Wi-\nFi"），保留连字符
        #expect(TextCleaner.removingLineBreaks("Wi-\nFi") == "Wi- Fi")
    }
}

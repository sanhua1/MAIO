/// 翻译功能（`FeatureTranslate`）提供的契约。
/// 调用方：截图 OCR（M5）识别出文字后，交给翻译窗口翻译。
public enum TranslateTextContract: CommandContract {
    public struct Input: Codable, Sendable, Equatable {
        public var text: String

        public init(text: String) {
            self.text = text
        }
    }

    public static let descriptor = CommandDescriptor(
        id: "translate.text",
        title: "翻译指定文字",
        summary: "打开翻译窗口并翻译传入的文字（供截图 OCR 等功能调用）",
        parameters: [ParameterSpec(key: "text", title: "文字", kind: .multilineText)],
    )
}

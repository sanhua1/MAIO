/// 截图功能（`FeatureScreenshot`）提供的契约。
/// 调用方：剪贴板历史（M2）右键"贴图"，把一条历史（图片或文字）钉到屏幕上。
public enum ScreenshotPinContract: CommandContract {
    public struct Input: Codable, Sendable, Equatable {
        /// 图片文件路径（PNG、TIFF 等）。调用方负责在调用结束后删除临时文件
        public var imagePath: String?
        /// 文字（渲染成图片后贴出）。imagePath 为空时使用
        public var text: String?

        public init(imagePath: String? = nil, text: String? = nil) {
            self.imagePath = imagePath
            self.text = text
        }
    }

    public static let descriptor = CommandDescriptor(
        id: "screenshot.pin",
        title: "贴图（指定图片或文字）",
        summary: "把图片文件或文字钉到屏幕上，并写入截图历史（供剪贴板历史等功能调用）",
        parameters: [
            ParameterSpec(key: "imagePath", title: "图片路径", kind: .text, isRequired: false),
            ParameterSpec(key: "text", title: "文字", kind: .multilineText, isRequired: false),
        ],
    )
}

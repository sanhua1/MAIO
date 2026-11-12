import MAIOKit

/// 剪贴板设置。字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
/// "在哪些 App 里 ⌃V 不弹出"不在这里：在「快捷键」页编辑这条绑定的生效范围。
struct ClipboardSettings: FeatureSettings {
    static let defaultValue = ClipboardSettings()

    enum PopupPosition: String, Codable, Sendable, CaseIterable {
        /// 文字光标处（拿不到时退回鼠标处）
        case caret
        case mouse
        case center

        var title: String {
            switch self {
            case .caret: "文字光标处"
            case .mouse: "鼠标处"
            case .center: "屏幕中央"
            }
        }
    }

    /// 弹出位置选"文字光标处"、但当前没有文字光标时（不在输入框里）用哪个位置
    enum CaretFallback: String, Codable, Sendable, CaseIterable {
        case center
        case mouse

        var title: String {
            switch self {
            case .center: "屏幕中央"
            case .mouse: "鼠标处"
            }
        }
    }

    /// 怎么开始搜索
    enum SearchMode: String, Codable, Sendable, CaseIterable {
        /// 按 ⌘F 或点搜索框才搜索；搜索时 ⏎ 结束搜索，再按 ⏎ 才粘贴（输入法打字时的 ⏎ 不会误粘贴）
        case explicit
        /// 打开面板直接打字就是搜索，⏎ 粘贴
        case typeToSearch

        var title: String {
            switch self {
            case .explicit: "按 ⌘F 或点搜索框才搜索"
            case .typeToSearch: "直接打字搜索"
            }
        }
    }

    var storageLimit: StorageLimit = .gb2
    var popupPosition: PopupPosition = .caret
    /// 默认屏幕中央（用户要求：没有文字光标时不要跟着鼠标）
    var caretFallback: CaretFallback = .center
    /// 默认要按 ⌘F 才搜索（用户要求：输入法打字时按 ⏎ 不要触发粘贴）
    var searchMode: SearchMode = .explicit
    /// 选中后直接粘贴到原来的 App；关闭时只放到剪贴板
    var pasteDirectly = true
    /// 粘贴过的条目移到最前
    var moveToTopOnPaste = true
    var recordRichText = true
    var recordImages = true
    var recordFiles = true
    /// 后台识别图片里的文字，搜索时也能搜到（系统 Vision，离线）
    var searchImageText = true
}

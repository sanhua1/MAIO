import MAIOKit

/// 翻译设置。字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
/// API Key 不在这里，存在钥匙串（ADR-0009）。
struct TranslateSettings: FeatureSettings {
    static let defaultValue = TranslateSettings()
    static let schemaVersion = 2

    /// v2：窗口默认改为屏幕正中间（用户要求），旧的"跟随鼠标"一并改过来
    static func migrate(_ json: inout JSONValue, from version: Int) throws {
        guard version < 2, case var .object(fields) = json, fields["windowPosition"] == .string("followMouse") else { return }
        fields["windowPosition"] = .string("center")
        json = .object(fields)
    }

    /// 快捷键（默认 ⌥Q）的行为
    enum HotkeyBehavior: String, Codable, Sendable, CaseIterable {
        /// 有选中文字就翻译选中的，没有就打开输入框
        case smart
        /// 总是打开空的输入框
        case inputOnly
        /// 只翻译选中的文字，没有选中时提示
        case selectionOnly

        var title: String {
            switch self {
            case .smart: "有选中文字就翻译，否则打开输入框"
            case .inputOnly: "总是打开输入框"
            case .selectionOnly: "只翻译选中的文字"
            }
        }
    }

    enum WindowPosition: String, Codable, Sendable, CaseIterable {
        case followMouse
        case remember
        case center

        var title: String {
            switch self {
            case .followMouse: "跟随鼠标"
            case .remember: "记住上次位置"
            case .center: "屏幕正中间"
            }
        }
    }

    /// 翻译选中文字时窗口放在哪（输入框模式用 windowPosition）
    enum SelectionPosition: String, Codable, Sendable, CaseIterable {
        case center
        case mouse
        /// 选中文字的下方（拿不到选中位置时用鼠标处）
        case nearSelection

        var title: String {
            switch self {
            case .center: "屏幕正中间"
            case .mouse: "鼠标处"
            case .nearSelection: "所选文字旁边"
            }
        }
    }

    var services: [ServiceConfig] = ServiceConfig.defaults
    var hotkeyBehavior: HotkeyBehavior = .smart
    /// 首选目标语言
    var targetLanguage: Language = .simplifiedChinese
    /// 原文已经是首选目标语言时，翻译成这个
    var secondTargetLanguage: Language = .english
    var removeLineBreaks = true
    var windowPosition: WindowPosition = .center
    var selectionWindowPosition: SelectionPosition = .center
    var closeOnBlur = true
    var fontSize = 14.0
    var historyEnabled = true
    var historyLimit = 500
    /// 记住的窗口位置（左上角，屏幕坐标），仅 windowPosition == .remember 时使用
    var rememberedOrigin: [Double]?
    var windowWidth = 460.0

    static let fontSizeRange = 11.0 ... 22.0
    static let historyLimits = [100, 500, 1000, 5000]
}

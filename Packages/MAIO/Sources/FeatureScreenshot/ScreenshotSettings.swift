import MAIOKit

/// 设置项：字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
struct ScreenshotSettings: FeatureSettings {
    static let defaultValue = ScreenshotSettings()
    /// 2：贴图缩放的默认修饰键从 ⌃ 改为不按修饰键（用户要求直接滚轮缩放）
    static let schemaVersion = 2

    static func migrate(_ json: inout JSONValue, from version: Int) throws {
        guard version < 2, case var .object(fields) = json, fields["pinZoomModifier"] == .string("control") else { return }
        fields["pinZoomModifier"] = .string("none")
        json = .object(fields)
    }

    /// 总是识别控件（关闭时按住 ⌘ 才识别控件，平时只识别窗口）
    var alwaysDetectControls = false
    var showMagnifier = true
    /// 取色的格式，截图时按 ⇧ 切换后会记住
    var colorFormat = ColorFormat.hex
    /// 保存文件夹，空表示默认的 ~/Pictures/MAIO
    var saveDirectory = ""
    /// ⌘S 时弹出"存储为"对话框
    var askSaveLocation = false
    /// 复制截图时也自动保存一份到保存文件夹
    var autoSave = false
    /// 截图历史的存储上限（用户选择默认 2 GB）
    var historyLimit = HistoryLimit.gb2
    /// 贴图默认显示主题色的发光阴影；关掉后是一张纯粹的图
    var pinShadow = true
    /// 贴图缩放：修饰键 + 滚轮（或 - =），默认不按修饰键（直接滚轮、直接按 - =）
    var pinZoomModifier = PinModifier.none
    /// 贴图透明度：修饰键 + 滚轮（或 - =），默认 ⌘
    var pinOpacityModifier = PinModifier.command

    var pinControls: PinControls {
        PinControls(zoomModifier: pinZoomModifier, opacityModifier: pinOpacityModifier)
    }

    /// 标注工具上次用过的颜色、大小、选项
    var toolStyle = ToolStyle()
}

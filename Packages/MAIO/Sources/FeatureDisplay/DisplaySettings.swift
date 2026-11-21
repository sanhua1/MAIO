import MAIOKit

/// 设置项：字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
struct DisplaySettings: FeatureSettings {
    static let defaultValue = DisplaySettings()

    /// 当前声音输出系统调不了、而且是一台能用 DDC 调音量的显示器时，音量键由 MAIO 接管
    var controlVolume = true
    /// 鼠标在能用 DDC 调亮度的外接显示器上时，亮度键由 MAIO 接管
    var controlBrightness = true
}

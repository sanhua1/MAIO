import MAIOKit

/// 设置项：字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
/// 设备级修饰键不在这里，直接读写系统的修饰键设置。
struct KeysSettings: FeatureSettings {
    static let defaultValue = KeysSettings()

    /// Super Caps（全局 Caps 分层）：打开后 Caps 原本的功能完全没有，单按什么都不发生
    var capsLayerEnabled = true
    var layer: [LayerEntry] = LayerEntry.defaults
    /// 全局改键（对所有键盘）
    var remaps: [KeyRemap] = []
    /// 鼠标中键、侧键
    var mouseRemaps: [MouseRemap] = []

    /// 键码 → 动作（同一个键有多条时用第一条）
    var layerMap: [UInt16: LayerAction] {
        layer.reduce(into: [:]) { map, entry in
            if map[entry.key.keyCode] == nil {
                map[entry.key.keyCode] = entry.action
            }
        }
    }
}

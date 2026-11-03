import MAIOKit

/// 设置项：字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
struct __NAME__Settings: FeatureSettings {
    static let defaultValue = __NAME__Settings()

    var isExampleEnabled = true
}

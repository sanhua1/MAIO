import MAIOKit

/// 全局设置（config/app.json）。
struct AppConfig: Codable, Equatable {
    struct FeatureEntry: Codable, Equatable {
        var enabled: Bool
    }

    var schemaVersion = 1
    /// 用户显式开关过的功能；不在这里的功能使用 manifest.enabledByDefault
    var features: [String: FeatureEntry] = [:]

    static let path = "config/app.json"
}

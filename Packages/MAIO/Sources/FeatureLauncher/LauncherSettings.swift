import MAIOKit

/// 启动器设置。字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
struct LauncherSettings: FeatureSettings {
    static let defaultValue = LauncherSettings()

    /// 关闭后这么多秒内再打开，保留上次的输入（0 = 每次都清空）
    var keepQuerySeconds: Double = 5
    /// "全部"里最多显示几个应用
    var maxAppsInAll = 5
    /// "全部"里最多显示几个文件
    var maxFilesInAll = 20
    /// 文件搜索（全盘索引）
    var fileSearchEnabled = true
    /// 额外不索引的目录
    var excludedPaths: [String] = []
    /// 索引 .app 等包的内部（多 50% 左右的条目）
    var indexPackageContents = false
    /// 输入为空时显示最近使用
    var showRecents = true
    /// "全部"的最后一项是"用默认引擎搜索…"
    var showWebFallback = true
    /// 默认搜索引擎的关键词
    var defaultEngine = "g"
    var engines: [WebSearchEngine] = WebSearchEngine.defaults

    var fallbackEngine: WebSearchEngine? {
        engines.first { $0.keyword == defaultEngine } ?? engines.first
    }
}

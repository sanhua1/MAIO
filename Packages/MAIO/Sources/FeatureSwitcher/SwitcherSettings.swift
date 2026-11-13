import MAIOKit

/// 窗口切换设置。触发键不在这里：在「MAIO 快捷键」页把任意组合键绑定到 `switcher.show`（默认 ⌥⇥）。
/// 字段只增不删；结构不兼容的修改要提升 schemaVersion 并实现 migrate。
struct SwitcherSettings: FeatureSettings {
    static let defaultValue = SwitcherSettings()

    /// 按下后多久才显示面板（秒）。在这之前松手会直接切到上一个窗口，不闪面板。
    var showDelay = 0.1
    /// 显示窗口缩略图（需要"屏幕与系统录音"权限，没有权限时显示 App 图标）
    var showThumbnails = true
    var showMinimizedWindows = true
    var showHiddenApps = true
    /// 显示没有打开窗口的 App（例如关掉所有窗口但仍在运行的访达）
    var showAppsWithoutWindows = false
    /// 每个 App 只显示一项（类似系统 ⌘⇥）
    var oneItemPerApp = false
    /// 不出现在切换器中的 App（bundle ID）
    var excludedBundleIDs: [String] = []

    static let showDelayRange = 0.0 ... 0.5
}

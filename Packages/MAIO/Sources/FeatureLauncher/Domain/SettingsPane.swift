/// 系统设置里的一个面板（"蓝牙""显示器"……），从系统的设置扩展里读出来，见 `SettingsPaneCatalog`
struct SettingsPane: Sendable, Equatable {
    /// 扩展的 bundle ID，打开时用 `x-apple.systempreferences:<id>`
    let id: String
    /// 当前语言的名称
    let name: String
    /// 其他能搜到的名称（英文名等）
    let otherNames: [String]
    /// 扩展包的路径（取图标用，和系统设置侧边栏里的图标一样）
    let path: String
    /// 随条件变化的图标（例如"电池"和"节能"），优先于扩展包的图标
    let iconType: String?
}

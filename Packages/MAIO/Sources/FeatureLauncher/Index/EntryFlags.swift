/// 索引里每一条的标志位（一个字节）
enum EntryFlags {
    static let directory: UInt8 = 1
    /// 名称以 . 开头，或带隐藏属性
    static let hidden: UInt8 = 2
    /// 本身是包（.app、.framework……），Finder 里显示成一个文件
    static let package: UInt8 = 4
    /// 在依赖目录里（node_modules、.git……），包括依赖目录本身。排序时靠后
    static let dependency: UInt8 = 8
    /// 在包里面（只有设置了"索引包的内容"才会有）
    static let insidePackage: UInt8 = 16
    /// 在用户目录里（排序加分）
    static let inHome: UInt8 = 32
    /// 已删除（增量更新时先打标记，存盘时再真正去掉）
    static let deleted: UInt8 = 64
    /// iCloud 占位（还没下载到本机），不往下扫，免得触发下载
    static let dataless: UInt8 = 128

    /// 子项从父目录继承的标志
    static let inherited: UInt8 = dependency | insidePackage | hidden | inHome

    /// 包的扩展名（参考 oil-find 的 Classifier）
    static let packageExtensions: Set<String> = [
        "app", "appex", "framework", "bundle", "plugin", "kext", "xpc", "photoslibrary", "musiclibrary",
        "xcarchive", "xcodeproj", "xcworkspace", "playground", "rtfd", "pages", "numbers", "key",
        "lproj", "momd", "scptd", "prefpane", "qlgenerator", "mdimporter", "saver", "component", "docarchive",
    ]

    /// 依赖、缓存、版本库目录（各个 App 自己的 Caches 也算）
    static let dependencyNames: Set<String> = [
        "Caches", "Cache", "CachedData", "Code Cache", "GPUCache",
        "node_modules", ".git", ".svn", ".hg", "Pods", "Carthage", "DerivedData", ".build", "__pycache__",
        ".venv", "venv", ".tox", ".gradle", ".m2", ".cargo", ".rustup", ".npm", ".pnpm-store", ".yarn",
        ".cache", "site-packages", ".next", ".nuxt", "bower_components", ".terraform", ".dart_tool", ".pub-cache",
    ]
}

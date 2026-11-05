import Foundation

/// 搜哪一类
enum LauncherSource: String, Codable, Sendable, CaseIterable {
    case all
    case apps
    case files
    case folders
    case commands

    var title: String {
        switch self {
        case .all: "全部"
        case .apps: "应用"
        case .files: "文件"
        case .folders: "文件夹"
        case .commands: "命令"
        }
    }

    /// 输入开头写这个前缀（后面跟空格）就只搜这一类；命令的 `>` 不需要空格
    var prefix: String? {
        switch self {
        case .all: nil
        case .apps: "a "
        case .files: "f "
        case .folders: "d "
        case .commands: ">"
        }
    }

    /// Tab 在这些之间切换
    static let available: [LauncherSource] = [.all, .apps, .files, .folders, .commands]

    /// 这个来源要不要搜文件
    var includesFiles: Bool {
        self == .all || self == .files || self == .folders
    }
}

/// 解析后的输入
struct LauncherQuery: Equatable {
    /// 实际搜索的来源（前缀优先于标签）
    var source: LauncherSource
    /// 去掉前缀后的文字
    var text: String
    /// 用了网页搜索引擎的关键词（`g 关键词`）
    var engine: WebSearchEngine?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func parse(
        _ raw: String, selected: LauncherSource, engines: [WebSearchEngine],
        available: [LauncherSource] = LauncherSource.available,
    ) -> LauncherQuery {
        for source in available {
            guard let prefix = source.prefix, raw.hasPrefix(prefix) else { continue }
            return LauncherQuery(source: source, text: String(raw.dropFirst(prefix.count)), engine: nil)
        }
        if let space = raw.firstIndex(of: " ") {
            let keyword = raw[..<space].lowercased()
            if let engine = engines.first(where: { $0.keyword.lowercased() == keyword }) {
                return LauncherQuery(source: .all, text: String(raw[raw.index(after: space)...]), engine: engine)
            }
        }
        return LauncherQuery(source: selected, text: raw, engine: nil)
    }
}

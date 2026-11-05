import Foundation

/// 文件搜索的结果
struct FileResults: Equatable {
    /// 是哪个输入的结果（和当前输入不一致时不显示）
    var query = ""
    var items: [LauncherItem] = []
    var total = 0
}

/// 把输入变成分好组、排好序的结果。
struct LauncherRanking {
    /// "应用"来源里最多显示多少个
    static let maxAppsInSource = 50
    static let recentLimit = 8
    /// "全部"里命令组最多显示多少个
    static let maxCommandsInAll = 3

    let apps: [LauncherItem]
    /// MAIO 命令、系统操作、系统设置面板
    var commands: [LauncherItem] = []
    /// 文件搜索的结果（异步到达；还没到时是空的）
    var files = FileResults()
    let usage: UsageBook
    /// 正在运行的应用（条目 ID），小幅加分
    let running: Set<String>
    let settings: LauncherSettings
    let now: Date

    func sections(for query: LauncherQuery) -> [LauncherSection] {
        if let engine = query.engine {
            let item = LauncherItem.web(engine, text: query.text)
            return item.map { [LauncherSection(title: "网页搜索", items: [$0])] } ?? []
        }
        if query.isEmpty {
            return recents(in: query.source)
        }
        var sections: [LauncherSection] = []
        switch query.source {
        case .all:
            let found = rank(apps, query.text, limit: settings.maxAppsInAll)
            if !found.isEmpty {
                sections.append(LauncherSection(title: "应用", items: found))
            }
            let commandsFound = rank(commands, query.text, limit: Self.maxCommandsInAll)
            if !commandsFound.isEmpty {
                sections.append(LauncherSection(title: "命令", items: commandsFound))
            }
            sections += fileSections(limit: settings.maxFilesInAll)
            if settings.showWebFallback, let engine = settings.fallbackEngine,
               let item = LauncherItem.web(engine, text: query.text) {
                sections.append(LauncherSection(title: "网页搜索", items: [item]))
            }
        case .apps:
            let found = rank(apps, query.text, limit: Self.maxAppsInSource)
            if !found.isEmpty {
                sections.append(LauncherSection(title: "应用", items: found))
            }
        case .files, .folders:
            sections += fileSections(limit: Int.max)
        case .commands:
            let found = rank(commands, query.text, limit: Self.maxAppsInSource)
            if !found.isEmpty {
                sections.append(LauncherSection(title: "命令", items: found))
            }
        }
        return sections
    }

    /// 文件组：索引给的顺序，从启动器打开过的往前提
    private func fileSections(limit: Int) -> [LauncherSection] {
        guard !files.items.isEmpty else { return [] }
        let ordered = files.items.enumerated().sorted { lhs, rhs in
            let left = usage.bonus(for: lhs.element.id, query: files.query, at: now) * 100 - lhs.offset
            let right = usage.bonus(for: rhs.element.id, query: files.query, at: now) * 100 - rhs.offset
            return left > right
        }.map(\.element)
        let title = files.total > files.items.count ? "文件（共 \(files.total) 个）" : "文件"
        return [LauncherSection(title: title, items: Array(ordered.prefix(limit)))]
    }

    /// 匹配的条目按 匹配质量 + 常用度 + 是否在运行 排序；同分的名称短的在前
    func rank(_ items: [LauncherItem], _ text: String, limit: Int) -> [LauncherItem] {
        let scored: [(item: LauncherItem, score: Int)] = items.compactMap { item in
            guard let match = MatchScore.score(text, in: item.keys) else { return nil }
            let extra = usage.bonus(for: item.id, query: text, at: now) + (running.contains(item.id) ? 3 : 0)
            return (item, match + extra)
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.item.title.count != rhs.item.title.count {
                return lhs.item.title.count < rhs.item.title.count
            }
            return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
        }
        .prefix(limit).map(\.item)
    }

    /// 输入为空时："全部""应用"显示最近使用；"命令"显示最近用过的命令 + 全部命令（按类别分组）
    private func recents(in source: LauncherSource) -> [LauncherSection] {
        let pool: [LauncherItem] = switch source {
        case .all: apps + commands
        case .apps: apps
        case .commands: commands
        case .files, .folders: []
        }
        var sections: [LauncherSection] = []
        if settings.showRecents, !pool.isEmpty {
            let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let items = usage.recent(limit: Self.recentLimit * 2, at: now).compactMap { byID[$0] }
            if !items.isEmpty {
                sections.append(LauncherSection(title: "最近使用", items: Array(items.prefix(Self.recentLimit))))
            }
        }
        if source == .commands {
            let shown = Set(sections.flatMap(\.items).map(\.id))
            sections += Self.commandGroups(commands.filter { !shown.contains($0.id) })
        }
        return sections
    }

    /// 全部命令，按 MAIO / 系统操作 / 系统设置 分组（保持原来的顺序）
    private static func commandGroups(_ commands: [LauncherItem]) -> [LauncherSection] {
        let groups = Dictionary(grouping: commands, by: \.kindLabel)
        return ["MAIO", "系统操作", "系统设置"].compactMap { label in
            groups[label].map { LauncherSection(title: label == "MAIO" ? "MAIO 命令" : label, items: $0) }
        }
    }
}

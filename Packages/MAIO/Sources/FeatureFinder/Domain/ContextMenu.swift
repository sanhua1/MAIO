/// Finder 右键菜单里 MAIO 加的项（扩展只负责显示，点击后交给主程序）
enum ContextMenuAction: String, Codable, CaseIterable, Sendable {
    case newFile
    case cut
    case paste
    case copyPath
    case openTerminal
    case toggleHidden

    var title: String {
        switch self {
        case .newFile: "新建"
        case .cut: "剪切"
        case .paste: "粘贴到这里"
        case .copyPath: "复制路径"
        case .openTerminal: "在终端中打开"
        case .toggleHidden: "显示 / 隐藏隐藏文件"
        }
    }

    var symbol: String {
        switch self {
        case .newFile: "doc.badge.plus"
        case .cut: "scissors"
        case .paste: "doc.on.clipboard"
        case .copyPath: "link"
        case .openTerminal: "terminal"
        case .toggleHidden: "eye"
        }
    }

    /// 在哪里右键时显示
    var places: [ContextMenuPlace] {
        switch self {
        case .newFile, .paste, .toggleHidden: [.container]
        case .cut: [.items]
        case .copyPath, .openTerminal: [.items, .container]
        }
    }
}

enum ContextMenuPlace: String, Codable, Sendable {
    /// 右键文件、文件夹
    case items
    /// 右键窗口空白处、桌面
    case container
}

/// 写给扩展的菜单配置（`data/finder/context-menu.json`）。扩展里有一份同样结构的解码代码，改字段要两边一起改
struct ContextMenuConfig: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// 点击后交给主程序的动作，例如 "cut"、"template:Word 文档.docx"
        var id: String
        var title: String
        var symbol: String?
        var places: [ContextMenuPlace]
        var children: [Entry]?
    }

    var entries: [Entry]

    /// 模板动作的 ID 前缀
    static let templatePrefix = "template:"

    static func make(enabled: Set<ContextMenuAction>, templates: [String]) -> ContextMenuConfig {
        let entries = ContextMenuAction.allCases.filter(enabled.contains).compactMap { action -> Entry? in
            guard action == .newFile else {
                return Entry(id: action.rawValue, title: action.title, symbol: action.symbol, places: action.places)
            }
            guard !templates.isEmpty else { return nil }
            let children = templates.map { file in
                Entry(id: templatePrefix + file, title: FileTemplates.title(of: file), places: action.places)
            }
            return Entry(
                id: action.rawValue,
                title: action.title,
                symbol: action.symbol,
                places: action.places,
                children: children,
            )
        }
        return ContextMenuConfig(entries: entries)
    }
}

/// 新建文件的模板：文件名决定菜单标题和新文件的名字
enum FileTemplates {
    /// "Word 文档.docx" → "Word 文档"
    static func title(of fileName: String) -> String {
        split(fileName).base
    }

    /// "新建文本文档.txt" → ("新建文本文档", ".txt")；没有扩展名时 ext 为空
    static func split(_ fileName: String) -> (base: String, ext: String) {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return (fileName, "") }
        return (String(fileName[..<dot]), String(fileName[dot...]))
    }

    /// 新文件的名字：模板名前面加"新建 "（和 Windows 一样）
    static func newFileName(for template: String) -> String {
        "新建 " + template
    }
}

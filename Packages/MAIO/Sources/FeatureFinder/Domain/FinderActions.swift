import MAIOKit

/// MAIO 补充的 Finder 动作（动作表的一行）。快捷键可改，可单独开关。
enum FinderActionID: String, Codable, CaseIterable, Sendable {
    case open
    case rename
    case trash
    case back
    case forward
    case enclosingFolder
    case goToFolder
    case cut
    case paste
    case newTextFile
    case openTerminal
}

/// 按下快捷键后做什么
enum FinderActionTarget: Sendable, Equatable {
    /// 改发 Finder 菜单项当前的快捷键（用户改过原生快捷键也能跟上）；找不到菜单项时用 fallback
    case menu(MenuPath, fallback: KeyChord)
    /// 改发固定的按键
    case key(KeyChord)
    /// 交给主线程处理
    case main
}

/// 菜单路径：同一个菜单项在不同系统语言下的路径，按顺序匹配
struct MenuPath: Sendable, Equatable {
    let candidates: [[String]]

    init(_ candidates: [String]...) {
        self.candidates = candidates
    }
}

struct FinderActionInfo: Sendable {
    let id: FinderActionID
    let title: String
    let help: String
    let defaultChord: KeyChord?
    let target: FinderActionTarget
    /// 按住不放时是否重复执行
    var repeats = false
}

extension FinderActionID {
    var info: FinderActionInfo {
        FinderActions.byID[self] ?? FinderActionInfo(id: self, title: rawValue, help: "", defaultChord: nil, target: .main)
    }
}

enum FinderActions {
    private static func key(_ code: UInt16, _ modifiers: KeyModifiers = []) -> KeyChord {
        KeyChord(keyCode: code, modifiers: modifiers)
    }

    typealias Key = FinderKeymap.Key

    static let all: [FinderActionInfo] = [
        FinderActionInfo(
            id: .open, title: "打开", help: FinderHelp.open, defaultChord: key(Key.returnKey),
            target: .menu(MenuPath(["文件", "打开"], ["File", "Open"]), fallback: key(Key.down, .command)),
        ),
        FinderActionInfo(
            id: .rename, title: "重命名", help: FinderHelp.rename, defaultChord: key(Key.f2),
            target: .key(key(Key.returnKey)),
        ),
        FinderActionInfo(
            id: .trash, title: "移到废纸篓", help: FinderHelp.trash, defaultChord: key(Key.forwardDelete),
            target: .menu(MenuPath(["文件", "移到废纸篓"], ["File", "Move to Trash"]), fallback: key(Key.delete, .command)),
        ),
        FinderActionInfo(
            id: .back, title: "后退", help: FinderHelp.back, defaultChord: key(Key.delete),
            target: .menu(MenuPath(["前往", "返回"], ["Go", "Back"]), fallback: key(Key.leftBracket, .command)),
            repeats: true,
        ),
        FinderActionInfo(
            id: .forward, title: "前进", help: FinderHelp.forward, defaultChord: nil,
            target: .menu(MenuPath(["前往", "前进"], ["Go", "Forward"]), fallback: key(Key.rightBracket, .command)),
            repeats: true,
        ),
        FinderActionInfo(
            id: .enclosingFolder, title: "上一级文件夹", help: FinderHelp.enclosing, defaultChord: key(Key.up, .option),
            target: .menu(MenuPath(["前往", "上层文件夹"], ["Go", "Enclosing Folder"]), fallback: key(Key.up, .command)),
            repeats: true,
        ),
        FinderActionInfo(
            id: .goToFolder, title: "输入路径跳转", help: FinderHelp.goTo, defaultChord: key(Key.l, .command),
            target: .menu(MenuPath(["前往", "前往文件夹…"], ["Go", "Go to Folder…"]), fallback: key(Key.g, [.command, .shift])),
        ),
        FinderActionInfo(
            id: .cut, title: "剪切", help: FinderHelp.cut, defaultChord: key(Key.x, .command), target: .main,
        ),
        FinderActionInfo(
            id: .paste, title: "粘贴（剪切后移动）", help: FinderHelp.paste, defaultChord: key(Key.v, .command),
            target: .menu(MenuPath(["编辑", "将项目移到这里"], ["Edit", "Move Item Here"]), fallback: key(Key.v, [.command, .option])),
        ),
        FinderActionInfo(
            id: .newTextFile, title: "新建文本文件", help: FinderHelp.newFile, defaultChord: key(Key.n, [.command, .option]),
            target: .main,
        ),
        FinderActionInfo(
            id: .openTerminal, title: "在终端中打开", help: FinderHelp.terminal, defaultChord: key(Key.t, [.command, .option]),
            target: .main,
        ),
    ]

    static let byID: [FinderActionID: FinderActionInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// ⌘C 的菜单项：剪切时改发它；用户按它时取消"待移动"
    static let copy = FinderActionTarget.menu(MenuPath(["编辑", "拷贝"], ["Edit", "Copy"]), fallback: key(Key.c, .command))
}

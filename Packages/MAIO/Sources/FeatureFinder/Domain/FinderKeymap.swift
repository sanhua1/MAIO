import MAIOKit

/// 改键过滤器的配置快照（tap 线程读取）：已经把设置和 Finder 菜单解析成"按键 → 动作"、"动作 → 要发的键"。
struct FinderKeyConfig: Sendable, Equatable {
    /// 触发键（不含 Fn）→ 动作
    var triggers: [KeyChord: FinderActionID] = [:]
    /// 动作 → 改发的组合键（只含 `.menu` / `.key` 类的动作）
    var targets: [FinderActionID: KeyChord] = [:]
    /// Finder 的"拷贝"
    var copyChord = KeyChord(keyCode: FinderKeymap.Key.c, modifiers: .command)
    /// 长按 ⌘ 显示速查面板
    var cheatSheet = true

    static let off = FinderKeyConfig(cheatSheet: false)
}

/// 需要主线程去做的事
enum FinderAction: Sendable, Equatable {
    /// 剪切：主线程发 `copy` 让 Finder 复制选中项，确认剪贴板里有文件后再标记"待移动"
    case cut(copy: KeyChord)
    case newTextFile
    case openTerminal
    /// Finder 在前台时修饰键变化（速查面板：只按住 ⌘ 一段时间后显示）
    case modifiers(KeyModifiers)
    /// 按住 ⌘ 期间按了别的键（速查面板取消）
    case keyWhileCommand
}

/// 过滤器的运行状态
struct FinderKeyState: Sendable, Equatable {
    /// Finder 的焦点在文本框里（重命名、搜索、前往文件夹），按键原样放行
    var isEditing = false
    /// 剪切之后、还没粘贴：下一次"粘贴"动作的按键改成"移到这里"
    var cutPending = false
}

/// Finder 里的 Windows 式按键（纯逻辑，ADR-0017）
enum FinderKeymap {
    static let bundleID = "com.apple.finder"

    enum Key {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let escape: UInt16 = 53
        static let f2: UInt16 = 120
        static let up: UInt16 = 126
        static let down: UInt16 = 125
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let c: UInt16 = 8
        static let g: UInt16 = 5
        static let l: UInt16 = 37
        static let n: UInt16 = 45
        static let t: UInt16 = 17
        static let v: UInt16 = 9
        static let x: UInt16 = 7
    }

    struct Result: Equatable {
        var decision: KeyFilterDecision
        var action: FinderAction?

        static let pass = Result(decision: .pass)
    }

    /// 比较按键时忽略 Fn（Fn 只是用来按出 F2、⌦ 的）；小键盘 Enter 等同回车
    static func normalized(_ chord: KeyChord) -> KeyChord {
        let code = chord.keyCode == Key.keypadEnter ? Key.returnKey : chord.keyCode
        return KeyChord(keyCode: code, modifiers: chord.modifiers.subtracting(.function))
    }

    static func decide(
        _ event: KeyEvent, frontmost: String?, config: FinderKeyConfig, state: inout FinderKeyState,
    ) -> Result {
        guard frontmost == bundleID else { return .pass }
        switch event.kind {
        case .flagsChanged:
            return config.cheatSheet ? Result(decision: .pass, action: .modifiers(event.modifiers)) : .pass
        case .up:
            return .pass
        case .down:
            let interrupt: FinderAction? = config.cheatSheet && event.modifiers.contains(.command) ? .keyWhileCommand : nil
            var result = state.isEditing ? .pass : keyDown(event, config, &state)
            result.action = result.action ?? interrupt
            return result
        }
    }

    private static func keyDown(_ event: KeyEvent, _ config: FinderKeyConfig, _ state: inout FinderKeyState) -> Result {
        let chord = normalized(event.chord)
        if chord == normalized(config.copyChord) {
            state.cutPending = false
        }
        guard let action = config.triggers[chord] else { return .pass }
        switch action {
        case .cut:
            return Result(decision: .consume, action: event.isRepeat ? nil : .cut(copy: config.copyChord))
        case .newTextFile, .openTerminal:
            let main: FinderAction = action == .newTextFile ? .newTextFile : .openTerminal
            return Result(decision: .consume, action: event.isRepeat ? nil : main)
        case .paste:
            guard state.cutPending, let target = config.targets[.paste] else { return .pass }
            state.cutPending = false
            return Result(decision: .replace(target))
        default:
            guard let target = config.targets[action] else { return .pass }
            if event.isRepeat, !action.info.repeats {
                return Result(decision: .consume)
            }
            return Result(decision: .replace(target))
        }
    }
}

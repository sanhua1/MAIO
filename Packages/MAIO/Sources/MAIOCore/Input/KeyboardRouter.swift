import MAIOKit

/// 已注册的按键过滤器（ADR-0017）
struct KeyFilterEntry {
    let token: FilterToken
    let filter: any RealtimeKeyFilter
}

/// 键盘事件路由决策（纯逻辑，可单测）。tap 线程据此执行副作用。
struct KeyboardRouter {
    enum Effect: Equatable {
        case toSession(KeyEvent)
        case toRecorder(KeyChord)
        case fire(CommandBinding)
        /// 按键过滤器要求改发的组合键
        case post(KeyChord)
    }

    struct Decision: Equatable {
        var consume: Bool
        var effect: Effect?

        static let pass = Decision(consume: false, effect: nil)
        static let swallow = Decision(consume: true, effect: nil)
    }

    var table: HotkeyTable = .empty
    var frontmost: String?
    var isRecording = false
    var hasSession = false
    var filters: [KeyFilterEntry] = []
    /// 已吞掉 keyDown 的键：对应的 keyUp 也要吞掉，否则前台 App 会收到孤立的 keyUp
    private(set) var swallowedKeys: Set<UInt16> = []
    /// 会话期间被过滤器改掉的键：原键码 → 交给会话的键码，松开时也按改后的键码交给会话
    private var sessionRemaps: [UInt16: UInt16] = [:]

    mutating func route(_ event: KeyEvent) -> Decision {
        switch event.kind {
        case .flagsChanged:
            if hasSession {
                return Decision(consume: false, effect: .toSession(event))
            }
            // 按键过滤器也能看到修饰键变化，但不能吞掉它
            if !isRecording {
                _ = filter(event)
            }
            return .pass
        case .up:
            if hasSession {
                // 会话期间松开的键（例如触发会话的那个 Tab）也要清掉记录，否则会话结束后会误吞一次 keyUp
                swallowedKeys.remove(event.keyCode)
                let keyCode = sessionRemaps.removeValue(forKey: event.keyCode) ?? event.keyCode
                let up = KeyEvent(kind: .up, keyCode: keyCode, modifiers: event.modifiers, isRepeat: event.isRepeat)
                return Decision(consume: true, effect: .toSession(up))
            }
            return swallowedKeys.remove(event.keyCode) != nil ? .swallow : .pass
        case .down:
            return routeKeyDown(event)
        }
    }

    private mutating func routeKeyDown(_ event: KeyEvent) -> Decision {
        if hasSession {
            return routeSessionKeyDown(event)
        }
        if isRecording {
            swallowedKeys.insert(event.keyCode)
            return event.isRepeat ? .swallow : Decision(consume: true, effect: .toRecorder(event.chord))
        }
        if let decision = filter(event) {
            return decision
        }
        guard let binding = table.match(event.chord, frontmost: frontmost) else { return .pass }
        swallowedKeys.insert(event.keyCode)
        // 按住不放产生的重复事件：吞掉但不重复执行
        return event.isRepeat ? .swallow : Decision(consume: true, effect: .fire(binding))
    }

    /// 会话期间先过选择加入的按键过滤器（ADR-0025，例如 Caps+WASD 在窗口切换里当方向键用）：
    /// 改成组合键的，把改后的键交给会话而不是发给系统；改成命令的直接吞掉，不交给会话。
    private mutating func routeSessionKeyDown(_ event: KeyEvent) -> Decision {
        switch filterDecision(event, inSession: true) {
        case nil, .pass:
            sessionRemaps.removeValue(forKey: event.keyCode)
            return Decision(consume: true, effect: .toSession(event))
        case .consume:
            return .swallow
        case let .replace(chord):
            sessionRemaps[event.keyCode] = chord.keyCode
            let remapped = KeyEvent(kind: .down, keyCode: chord.keyCode, modifiers: chord.modifiers, isRepeat: event.isRepeat)
            return Decision(consume: true, effect: .toSession(remapped))
        }
    }

    /// 按注册顺序问过滤器，第一个不是 pass 的结果生效
    private mutating func filter(_ event: KeyEvent) -> Decision? {
        switch filterDecision(event) {
        case nil, .pass:
            return nil
        case .consume:
            swallowedKeys.insert(event.keyCode)
            return .swallow
        case let .replace(chord):
            swallowedKeys.insert(event.keyCode)
            return Decision(consume: true, effect: .post(chord))
        }
    }

    /// 第一个不是 pass 的过滤器结果；修饰键变化只通知、不采纳结果
    private func filterDecision(_ event: KeyEvent, inSession: Bool = false) -> KeyFilterDecision? {
        guard !filters.isEmpty else { return nil }
        let environment = RealtimeEnvironment(frontmostBundleID: frontmost, modifiers: event.modifiers)
        for entry in filters where !inSession || entry.filter.appliesDuringKeyboardSessions {
            let decision = entry.filter.process(event, environment)
            if decision == .pass || event.kind == .flagsChanged {
                continue
            }
            return decision
        }
        return nil
    }
}

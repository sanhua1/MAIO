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
                return Decision(consume: true, effect: .toSession(event))
            }
            return swallowedKeys.remove(event.keyCode) != nil ? .swallow : .pass
        case .down:
            return routeKeyDown(event)
        }
    }

    private mutating func routeKeyDown(_ event: KeyEvent) -> Decision {
        if hasSession {
            return Decision(consume: true, effect: .toSession(event))
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

    /// 按注册顺序问过滤器，第一个不是 pass 的结果生效
    private mutating func filter(_ event: KeyEvent) -> Decision? {
        guard !filters.isEmpty else { return nil }
        let environment = RealtimeEnvironment(frontmostBundleID: frontmost, modifiers: event.modifiers)
        for entry in filters {
            switch entry.filter.process(event, environment) {
            case .pass: continue
            case _ where event.kind == .flagsChanged: continue
            case .consume:
                swallowedKeys.insert(event.keyCode)
                return .swallow
            case let .replace(chord):
                swallowedKeys.insert(event.keyCode)
                return Decision(consume: true, effect: .post(chord))
            }
        }
        return nil
    }
}

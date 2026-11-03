import CoreGraphics
import MAIOKit

/// MAIO 合成事件的标记，写在 eventSourceUserData 字段里。
enum SyntheticMarker {
    static let value: Int64 = 0x4D41_494F // "MAIO"

    static func isMarked(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == value
    }
}

/// 发送合成事件（线程安全）。发送位置是会话层，不会再次经过 MAIO 自己的 HID 层 tap。
final class EventPoster: SyntheticEventPoster {
    func post(_ event: SyntheticEvent) {
        switch event {
        case let .keyStroke(chord): postKeyStroke(chord)
        case let .scroll(deltaY, deltaX, phase, momentumPhase):
            postScroll(deltaY: deltaY, deltaX: deltaX, phase: phase, momentumPhase: momentumPhase)
        case let .magnify(phase, magnification): postMagnify(phase: phase, magnification: magnification)
        }
    }

    // 参考：references/LinearMouse/Modules/GestureKit/Sources/GestureKit/GestureEvent+Zoom.swift（MIT）
    /// 触控板捏合手势：NSEventTypeGesture（29）+ 私有字段。字段号来自 WebKit 的 CoreGraphicsTestSPI.h：
    /// 110 = 手势的 HID 类型（8 = 缩放），113 = 缩放量，132 = 手势阶段。
    private func postMagnify(phase: ScrollPhase, magnification: Double) {
        guard let event = CGEvent(source: nil), let type = CGEventType(rawValue: 29),
              let hidType = CGEventField(rawValue: 110), let zoomValue = CGEventField(rawValue: 113),
              let gesturePhase = CGEventField(rawValue: 132) else { return }
        event.type = type
        // 不带修饰键：用户按着 ⌘ 只是为了触发缩放，不能让 App 当成"⌘ + 捏合"
        event.flags = []
        event.setIntegerValueField(hidType, value: 8)
        event.setIntegerValueField(gesturePhase, value: Self.gesturePhase(phase))
        event.setDoubleValueField(zoomValue, value: magnification)
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticMarker.value)
        event.post(tap: .cgSessionEventTap)
    }

    /// CGSGesturePhase
    static func gesturePhase(_ phase: ScrollPhase) -> Int64 {
        switch phase {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 4
        case .cancelled: 8
        case .mayBegin: 128
        }
    }

    private func postKeyStroke(_ chord: KeyChord) {
        let source = CGEventSource(stateID: .privateState)
        let flags = Self.flags(for: chord.modifiers)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticMarker.value)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func postScroll(deltaY: Double, deltaX: Double, phase: ScrollPhase, momentumPhase: MomentumPhase) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY.rounded()),
            wheel2: Int32(deltaX.rounded()),
            wheel3: 0,
        ) else { return }
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: ScrollEventCodec.rawPhase(phase))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: ScrollEventCodec.rawMomentum(momentumPhase))
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticMarker.value)
        event.post(tap: .cgSessionEventTap)
    }

    // 参考：references/Maccy/Maccy/Clipboard.swift（paste()，源自 Flycut PR #18）
    /// 除了通用标志位，还带上"左侧修饰键"的设备标志位（NX_DEVICEL*KEYMASK）。
    /// 有些 App 只认带设备位的 ⌘V，否则不粘贴。
    static func flags(for modifiers: KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
            flags.insert(CGEventFlags(rawValue: 0x08))
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
            flags.insert(CGEventFlags(rawValue: 0x02))
        }
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
            flags.insert(CGEventFlags(rawValue: 0x01))
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
            flags.insert(CGEventFlags(rawValue: 0x20))
        }
        if modifiers.contains(.function) {
            flags.insert(.maskSecondaryFn)
        }
        return flags
    }

    static func modifiers(from flags: CGEventFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.maskCommand) {
            result.insert(.command)
        }
        if flags.contains(.maskShift) {
            result.insert(.shift)
        }
        if flags.contains(.maskControl) {
            result.insert(.control)
        }
        if flags.contains(.maskAlternate) {
            result.insert(.option)
        }
        if flags.contains(.maskSecondaryFn) {
            result.insert(.function)
        }
        return result
    }
}

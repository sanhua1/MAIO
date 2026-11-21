import MAIOKit

/// 媒体键的识别与过滤（ADR-0028，纯逻辑，可单测）。
///
/// 媒体键有两种来源：
/// - `NX_SYSDEFINED`（事件类型 14，子类型 8）：外接键盘、鼠标侧键发出的 HID Consumer 音量 / 亮度键，
///   `data1` = 键类型 << 16 | 状态 << 8 | 重复位（状态 0xA 按下、0xB 抬起）
/// - 普通 keyDown / keyUp，键码 144 / 145：苹果键盘的亮度键
struct MediaKeyRouter {
    struct Entry {
        let token: FilterToken
        let filter: any RealtimeMediaKeyFilter
    }

    static let systemDefinedType: UInt32 = 14
    static let mediaKeySubtype: Int16 = 8
    static let brightnessUpKeyCode: UInt16 = 144
    static let brightnessDownKeyCode: UInt16 = 145

    /// 媒体键的来源
    enum Source: Sendable, Hashable {
        /// NX_SYSDEFINED（外接键盘、鼠标侧键 / 滚轮绑的媒体键）
        case systemDefined
        /// keyDown 144 / 145（苹果键盘的亮度键）
        case keyCode
    }

    /// 同一次按下从两个来源各来一个事件时，两者之间的最大间隔（纳秒）
    static let twinWindow: UInt64 = 30_000_000

    var filters: [Entry] = []
    /// 按下被吞掉的键：对应的抬起也要吞掉
    private var consumed: Set<MediaKey> = []
    /// 每个键上一次按下：来源、时间、是否吞掉
    private var lastDown: [MediaKey: (source: Source, time: UInt64, consumed: Bool)] = [:]

    /// 解析 NX_SYSDEFINED 的 data1。返回 nil 表示不是我们关心的媒体键。
    static func decode(subtype: Int16, data1: Int) -> (key: MediaKey, isDown: Bool, isRepeat: Bool)? {
        guard subtype == mediaKeySubtype else { return nil }
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        let key: MediaKey
        switch keyType {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        case 7: key = .mute
        default: return nil
        }
        switch state {
        case 0xA: return (key, true, data1 & 0x1 != 0)
        case 0xB: return (key, false, false)
        default: return nil
        }
    }

    static func brightnessKey(keyCode: UInt16) -> MediaKey? {
        switch keyCode {
        case brightnessUpKeyCode: .brightnessUp
        case brightnessDownKeyCode: .brightnessDown
        default: nil
        }
    }

    /// 返回 true 表示吞掉这个事件。`time` 是事件时间戳（纳秒）。
    /// 同一个来源连续来的按下一个都不丢（鼠标滚轮绑的音量键可能几毫秒一个）；
    /// 只有"另一个来源在 30 毫秒内来的同一个键"才当成同一次按下的副本，沿用前一个的结果、不再交给过滤器。
    mutating func route(
        key: MediaKey, isDown: Bool, isRepeat: Bool, modifiers: KeyModifiers,
        source: Source = .systemDefined, time: UInt64 = 0,
    ) -> Bool {
        guard isDown else {
            return consumed.remove(key) != nil
        }
        if !isRepeat, let last = lastDown[key], last.source != source, time >= last.time,
           time - last.time <= Self.twinWindow {
            lastDown[key] = nil
            if last.consumed {
                consumed.insert(key)
            }
            return last.consumed
        }
        let event = MediaKeyEvent(key: key, isRepeat: isRepeat, modifiers: modifiers)
        let consume = filters.contains { $0.filter.process(event) == .consume }
        lastDown[key] = (source, time, consume)
        if consume {
            consumed.insert(key)
        } else {
            consumed.remove(key)
        }
        return consume
    }
}

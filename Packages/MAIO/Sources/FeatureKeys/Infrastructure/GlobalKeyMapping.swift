import Foundation

/// MAIO 在 HID 层的全局映射（事件系统的 `UserKeyMapping`，等同 `hidutil property --set`，对所有键盘生效）：
/// - Caps 分层打开时，Caps → "无操作"（和系统修饰键设置里的"无操作"同一个值）：不切换大写锁定、不亮灯、不发出任何键，
///   按下 / 松开由 `CapsKeyMonitor` 从设备的原始输入里读；
/// - 全局改键里"单键换单键"的条目。
///
/// 不写偏好，退出登录 / 重启后自动消失（MAIO 启动时重新设）。别的工具写的映射原样保留：只替换 MAIO 上次写的和这次要写的来源键。
@MainActor
final class GlobalKeyMapping {
    static let property = "UserKeyMapping"
    static let capsLock = MappingPair(source: HIDUsage.keyboard(0x39), destination: HIDUsage.noAction)

    private let keyboards: HIDKeyboards
    /// 上次写进去的（用来在删除条目时把它们拿掉）
    private var applied: [MappingPair] = []

    init(keyboards: HIDKeyboards) {
        self.keyboards = keyboards
    }

    @discardableResult
    func apply(_ pairs: [MappingPair]) -> Bool {
        let sources = Set(pairs.map(\.source))
        let previous = Set(applied)
        let others = keyboards.globalPairs(Self.property).filter { !previous.contains($0) && !sources.contains($0.source) }
        guard keyboards.setGlobalPairs(others + pairs, Self.property) else { return false }
        applied = pairs
        return true
    }

    func removeAll() {
        apply([])
    }
}

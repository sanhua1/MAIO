import Foundation

/// 系统的修饰键设置：和系统设置"键盘 › 键盘快捷键 › 修饰键"是同一份。
/// 偏好存在当前主机的全局偏好里（`defaults -currentHost read -g`），HID 层的属性让它立即生效；
/// 键盘重新接上时系统自己从偏好里读出来再设一次（P1 实验 ③ 实测），所以不用监听插拔。
struct ModifierMappingStore {
    let keyboards: HIDKeyboards

    /// 保存的设置；没保存过时用键盘上当前生效的（例如用 hidutil 设的）
    func mapping(for device: DeviceKey) -> ModifierMapping {
        savedMapping(for: device) ?? ModifierMapping(pairs: keyboards.currentPairs(of: device) ?? [])
    }

    /// 偏好里保存的设置；没保存过时 nil
    func savedMapping(for device: DeviceKey) -> ModifierMapping? {
        CFPreferencesCopyValue(
            device.preferenceKey as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost,
        ).map { ModifierMapping(pairs: HIDKeyboards.pairs(from: $0)) }
    }

    /// 写入偏好并立即生效。返回 false 表示键盘上没设成功（偏好已经写了，重新接上键盘后生效）
    @discardableResult
    func save(_ mapping: ModifierMapping, for device: DeviceKey) -> Bool {
        let pairs = mapping.pairs
        let value: CFArray? = pairs.isEmpty ? nil : HIDKeyboards.plist(pairs) as CFArray
        CFPreferencesSetValue(
            device.preferenceKey as CFString, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost,
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return keyboards.apply(pairs, to: device)
    }
}

import Foundation

/// 键盘的身份：厂商 ID + 产品 ID。系统的修饰键设置也按这两个值区分键盘。
struct DeviceKey: Hashable, Sendable {
    let vendorID: Int
    let productID: Int

    /// 系统存修饰键设置用的偏好键（当前主机的全局偏好）
    var preferenceKey: String {
        "com.apple.keyboard.modifiermapping.\(vendorID)-\(productID)-0"
    }
}

/// 一个接着的键盘
struct KeyboardDevice: Hashable, Sendable, Identifiable {
    let key: DeviceKey
    let name: String
    let isBuiltIn: Bool

    var id: DeviceKey {
        key
    }

    var displayName: String {
        isBuiltIn ? "Mac 自带键盘" : name
    }

    /// 自带键盘排第一，其他按名称
    static func sorted(_ devices: [KeyboardDevice]) -> [KeyboardDevice] {
        devices.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

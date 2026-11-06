import Foundation
import IOKit.hid

/// 系统 HID 层的键盘服务：列出键盘、读写它们的修饰键映射（`HIDKeyboardModifierMappingPairs`）。
///
/// 写这个属性要用 monitor 类型的 `IOHIDEventSystemClient`：公开的 `IOHIDEventSystemClientCreateSimpleClient`
/// 读不到也写不了，admin 类型拿不到服务（要 entitlement）。`IOHIDEventSystemClientCreateWithType` 是 IOKit
/// 导出的函数，只是不在公开头文件里，运行时查找；系统设置的键盘面板用的也是它（见 docs/specs/M8-keys.md 5.3a）。
final class HIDKeyboards {
    static let mappingProperty = "HIDKeyboardModifierMappingPairs"
    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"
    /// kIOHIDEventSystemClientTypeMonitor
    private static let monitorType: Int32 = 1

    private let client: IOHIDEventSystemClient?

    init() {
        client = Self.makeClient()
    }

    var isAvailable: Bool {
        client != nil
    }

    /// 接着的键盘（同一个键盘的多个服务合成一个；不含 Karabiner 的虚拟键盘）
    func keyboards() -> [KeyboardDevice] {
        var seen = Set<DeviceKey>()
        let devices = keyboardServices().compactMap { service -> KeyboardDevice? in
            guard let key = Self.deviceKey(service), seen.insert(key).inserted else { return nil }
            let name = Self.property(service, kIOHIDProductKey) as? String ?? "未知键盘"
            guard !name.localizedCaseInsensitiveContains("Karabiner") else { return nil }
            let builtIn = Self.property(service, kIOHIDBuiltInKey) as? Bool ?? false
            return KeyboardDevice(key: key, name: name, isBuiltIn: builtIn)
        }
        return KeyboardDevice.sorted(devices)
    }

    /// 键盘当前生效的映射（第一个服务上的）
    func currentPairs(of device: DeviceKey) -> [MappingPair]? {
        guard let service = keyboardServices().first(where: { Self.deviceKey($0) == device }) else { return nil }
        return Self.pairs(from: Self.property(service, Self.mappingProperty))
    }

    /// 给这个键盘的所有服务设映射，立即生效。有一个服务设成功就返回 true
    @discardableResult
    func apply(_ pairs: [MappingPair], to device: DeviceKey) -> Bool {
        let value = Self.plist(pairs) as CFArray
        var applied = false
        for service in keyboardServices() where Self.deviceKey(service) == device {
            applied = IOHIDServiceClientSetProperty(service, Self.mappingProperty as CFString, value) || applied
        }
        return applied
    }

    /// 事件系统的全局映射属性（例如 `UserKeyMapping`），对所有键盘服务生效
    func globalPairs(_ property: String) -> [MappingPair] {
        guard let client else { return [] }
        return Self.pairs(from: IOHIDEventSystemClientCopyProperty(client, property as CFString))
    }

    func setGlobalPairs(_ pairs: [MappingPair], _ property: String) -> Bool {
        guard let client else { return false }
        return IOHIDEventSystemClientSetProperty(client, property as CFString, Self.plist(pairs) as CFArray)
    }

    // MARK: - 转换

    static func plist(_ pairs: [MappingPair]) -> [[String: Int]] {
        pairs.map { [sourceKey: Int(truncatingIfNeeded: $0.source), destinationKey: Int(truncatingIfNeeded: $0.destination)] }
    }

    static func pairs(from value: Any?) -> [MappingPair] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let source = (item[sourceKey] as? NSNumber)?.uint64Value,
                  let destination = (item[destinationKey] as? NSNumber)?.uint64Value
            else { return nil }
            return MappingPair(source: source, destination: destination)
        }
    }

    // MARK: - 私有

    private func keyboardServices() -> [IOHIDServiceClient] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        return services.filter {
            IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0
        }
    }

    private static func deviceKey(_ service: IOHIDServiceClient) -> DeviceKey? {
        guard let vendor = property(service, kIOHIDVendorIDKey) as? Int,
              let product = property(service, kIOHIDProductIDKey) as? Int
        else { return nil }
        return DeviceKey(vendorID: vendor, productID: product)
    }

    private static func property(_ service: IOHIDServiceClient, _ key: String) -> Any? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    private static func makeClient() -> IOHIDEventSystemClient? {
        typealias Create = @convention(c) (CFAllocator?, Int32, CFDictionary?) -> Unmanaged<IOHIDEventSystemClient>?
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let symbol = dlsym(handle, "IOHIDEventSystemClientCreateWithType")
        else { return nil }
        let create = unsafeBitCast(symbol, to: Create.self)
        return create(kCFAllocatorDefault, monitorType, nil)?.takeRetainedValue()
    }
}

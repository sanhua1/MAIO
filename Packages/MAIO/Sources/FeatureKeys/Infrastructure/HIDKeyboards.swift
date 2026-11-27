import Dispatch
import Foundation
import IOKit.hid
import Synchronization

/// 键盘热插拔监听的句柄。取消或释放后停止监听。
protocol KeyboardAttachmentWatch: AnyObject {
    func cancel()
}

/// 键盘 HID 服务抽象，方便单测替换。
protocol KeyboardHID {
    var isAvailable: Bool { get }
    func keyboards() -> [KeyboardDevice]
    func currentPairs(of device: DeviceKey) -> [MappingPair]?
    @discardableResult
    func apply(_ pairs: [MappingPair], to device: DeviceKey) -> Bool
    func watchAttachments(_ onAttach: @escaping @Sendable () -> Void) -> (any KeyboardAttachmentWatch)?
}

/// 系统 HID 层的键盘服务：列出键盘、读写它们的修饰键映射（`HIDKeyboardModifierMappingPairs`）、监听新键盘接入。
///
/// 写这个属性要用 monitor 类型的 `IOHIDEventSystemClient`：公开的 `IOHIDEventSystemClientCreateSimpleClient`
/// 读不到也写不了，admin 类型拿不到服务（要 entitlement）。`IOHIDEventSystemClientCreateWithType` 是 IOKit
/// 导出的函数，只是不在公开头文件里，运行时查找；系统设置的键盘面板用的也是它（见 docs/specs/M8-keys.md 5.3a）。
///
/// `IOHIDEventSystemClientCopyServices` 只读客户端内部缓存的服务字典，不主动向 WindowServer 查询；
/// 长期持有未 schedule 的客户端会在键盘拔插后永远返回失效的旧句柄，并且导致 WindowServer 推送设备通知超时（0x10000004）。
/// 因此每次读写按需创建临时客户端，热插拔监听单独使用 schedule + activate 的客户端。
final class HIDKeyboards: KeyboardHID {
    static let mappingProperty = "HIDKeyboardModifierMappingPairs"
    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"

    var isAvailable: Bool {
        withClient { _ in true } ?? false
    }

    /// 接着的键盘（同一个键盘的多个服务合成一个；不含 Karabiner 的虚拟键盘）
    func keyboards() -> [KeyboardDevice] {
        withClient { client in
            var seen = Set<DeviceKey>()
            let devices = Self.keyboardServices(in: client).compactMap { service -> KeyboardDevice? in
                guard let key = Self.deviceKey(service), seen.insert(key).inserted else { return nil }
                let name = Self.property(service, kIOHIDProductKey) as? String ?? "未知键盘"
                guard !name.localizedCaseInsensitiveContains("Karabiner") else { return nil }
                let builtIn = Self.property(service, kIOHIDBuiltInKey) as? Bool ?? false
                return KeyboardDevice(key: key, name: name, isBuiltIn: builtIn)
            }
            return KeyboardDevice.sorted(devices)
        } ?? []
    }

    /// 键盘当前生效的映射（第一个服务上的）
    func currentPairs(of device: DeviceKey) -> [MappingPair]? {
        withClient { client in
            guard let service = Self.keyboardServices(in: client).first(where: { Self.deviceKey($0) == device }) else {
                return nil
            }
            return Self.pairs(from: Self.property(service, Self.mappingProperty))
        }
    }

    /// 给这个键盘的所有服务设映射，立即生效。有一个服务设成功就返回 true
    @discardableResult
    func apply(_ pairs: [MappingPair], to device: DeviceKey) -> Bool {
        withClient { client in
            let value = Self.plist(pairs) as CFArray
            var applied = false
            for service in Self.keyboardServices(in: client) where Self.deviceKey(service) == device {
                applied = IOHIDServiceClientSetProperty(service, Self.mappingProperty as CFString, value) || applied
            }
            return applied
        } ?? false
    }

    /// 监听新键盘服务接入（拔插、无线唤醒重连、显示器 USB Hub 唤醒等）
    func watchAttachments(_ onAttach: @escaping @Sendable () -> Void) -> (any KeyboardAttachmentWatch)? {
        HIDAttachmentWatch(onAttach: onAttach)
    }

    /// 事件系统的全局映射属性（例如 `UserKeyMapping`），对所有键盘服务生效
    func globalPairs(_ property: String) -> [MappingPair] {
        withClient { client in
            Self.pairs(from: IOHIDEventSystemClientCopyProperty(client, property as CFString))
        } ?? []
    }

    func setGlobalPairs(_ pairs: [MappingPair], _ property: String) -> Bool {
        withClient { client in
            IOHIDEventSystemClientSetProperty(client, property as CFString, Self.plist(pairs) as CFArray)
        } ?? false
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

    private func withClient<T>(_ body: (IOHIDEventSystemClient) -> T?) -> T? {
        autoreleasepool {
            guard let client = HIDClientAPI.makeMonitorClient() else { return nil }
            return body(client)
        }
    }

    private static func keyboardServices(in client: IOHIDEventSystemClient) -> [IOHIDServiceClient] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
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
}

/// 运行时加载 IOKit 里不在公开头文件中的事件系统客户端接口（只查找一次）
private enum HIDClientAPI {
    /// kIOHIDEventSystemClientTypeMonitor
    static let monitorType: Int32 = 1

    typealias Create = @convention(c) (CFAllocator?, Int32, CFDictionary?) -> Unmanaged<IOHIDEventSystemClient>?
    typealias SetMatching = @convention(c) (IOHIDEventSystemClient, CFDictionary?) -> Void
    typealias DeviceMatchingCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, IOHIDServiceClient)
        -> Void
    typealias RegisterDeviceMatching = @convention(c) (
        IOHIDEventSystemClient, DeviceMatchingCallback?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
    ) -> Void
    typealias SetDispatchQueue = @convention(c) (IOHIDEventSystemClient, DispatchQueue) -> Void
    typealias Activate = @convention(c) (IOHIDEventSystemClient) -> Void
    typealias Cancel = @convention(c) (IOHIDEventSystemClient) -> Void
    typealias SetCancelHandler = @convention(c) (IOHIDEventSystemClient, @escaping @Sendable @convention(block) () -> Void)
        -> Void

    nonisolated(unsafe) static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    static let create: Create? = load("IOHIDEventSystemClientCreateWithType")
    static let setMatching: SetMatching? = load("IOHIDEventSystemClientSetMatching")
    static let registerDeviceMatching: RegisterDeviceMatching? = load("IOHIDEventSystemClientRegisterDeviceMatchingCallback")
    static let setDispatchQueue: SetDispatchQueue? = load("IOHIDEventSystemClientSetDispatchQueue")
    static let activate: Activate? = load("IOHIDEventSystemClientActivate")
    static let cancel: Cancel? = load("IOHIDEventSystemClientCancel")
    static let setCancelHandler: SetCancelHandler? = load("IOHIDEventSystemClientSetCancelHandler")

    static func makeMonitorClient() -> IOHIDEventSystemClient? {
        create?(kCFAllocatorDefault, monitorType, nil)?.takeRetainedValue()
    }

    private static func load<T>(_ name: String) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}

/// 用已调度并激活的 monitor 客户端监听新键盘接入；cancel 时经由 cancelHandler 安全释放回调上下文。
private final class HIDAttachmentWatch: KeyboardAttachmentWatch {
    private final class CallbackBox: Sendable {
        let handler: Mutex<(@Sendable () -> Void)?>

        init(_ onAttach: @escaping @Sendable () -> Void) {
            handler = Mutex(onAttach)
        }

        func invoke() {
            let fn = handler.withLock { $0 }
            fn?()
        }

        func invalidate() {
            handler.withLock { $0 = nil }
        }
    }

    /// 跨 cancelHandler 传递的非 Sendable 指针包装（仅在 IOKit 保证取消完成后释放）
    private struct RetainedCleanup: @unchecked Sendable {
        let client: Unmanaged<IOHIDEventSystemClient>
        let box: Unmanaged<CallbackBox>

        func release() {
            box.release()
            client.release()
        }
    }

    private let lock = NSLock()
    private var client: IOHIDEventSystemClient?
    private let callbackBox: CallbackBox

    init?(onAttach: @escaping @Sendable () -> Void) {
        guard let setMatching = HIDClientAPI.setMatching,
              let registerMatching = HIDClientAPI.registerDeviceMatching,
              let setQueue = HIDClientAPI.setDispatchQueue,
              let activate = HIDClientAPI.activate,
              let setCancelHandler = HIDClientAPI.setCancelHandler,
              let client = HIDClientAPI.makeMonitorClient()
        else { return nil }

        let box = CallbackBox(onAttach)
        self.client = client
        callbackBox = box

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        setMatching(client, matching as CFDictionary)

        let rawBox = Unmanaged.passRetained(box)
        let retainedClient = Unmanaged.passRetained(client)
        let cleanup = RetainedCleanup(client: retainedClient, box: rawBox)

        registerMatching(client, { target, _, _ in
            guard let target else { return }
            Unmanaged<CallbackBox>.fromOpaque(target).takeUnretainedValue().invoke()
        }, rawBox.toOpaque(), nil)

        setCancelHandler(client) {
            cleanup.release()
        }

        let queue = DispatchQueue(label: "app.maio.keys.hid-watch")
        setQueue(client, queue)
        activate(client)
    }

    deinit {
        cancel()
    }

    func cancel() {
        callbackBox.invalidate()
        guard let client = lock.withLock({ () -> IOHIDEventSystemClient? in
            let existing = self.client
            self.client = nil
            return existing
        }) else { return }
        HIDClientAPI.registerDeviceMatching?(client, nil, nil, nil)
        HIDClientAPI.cancel?(client)
    }
}

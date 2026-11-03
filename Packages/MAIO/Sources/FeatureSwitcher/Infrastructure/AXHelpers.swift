import ApplicationServices
import CoreGraphics

/// 辅助功能元素 → CGWindowID。私有函数，但被几乎所有窗口管理工具使用（alt-tab-macos、Rectangle、Hammerspoon），
/// 自 macOS 10.x 起一直稳定（见 ADR-0008）。注意：对子元素调用会返回父窗口的 ID，调用前要确认角色是 AXWindow。
@_silgen_name("_AXUIElementGetWindow")
private func axUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXHelper {
    /// 单个 App 无响应时，最多等待这么久（秒），避免整个切换器卡住
    static let messagingTimeout: Float = 0.15

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return axUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    static func attribute<T>(_ element: AXUIElement, _ name: String, as _: T.Type = T.self) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func size(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }
}

/// AXUIElement 不是 Sendable，但它只是一个跨进程引用，在线程间传递是安全的。
struct AXElementBox: @unchecked Sendable {
    let element: AXUIElement
}

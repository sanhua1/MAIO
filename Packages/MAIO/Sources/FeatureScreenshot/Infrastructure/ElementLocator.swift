import AppKit

/// 用辅助功能识别鼠标下的控件。
///
/// 遮罩盖在最上层，系统级命中测试会命中 MAIO 自己；所以直接问鼠标下那个 App：
/// 在它的应用元素上调用 `AXUIElementCopyElementAtPosition`（ADR-0011 实验已验证）。
/// 偶尔一次查询要 20 ms，所以放在后台串行队列里执行。
final class ElementLocator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.maio.screenshot.element-locator", qos: .userInteractive)

    /// 返回控件的范围（全局坐标，左上角原点）。
    func frame(at point: CGPoint, pid: Int32) async -> CGRect? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.query(point, pid: pid))
            }
        }
    }

    private static func query(_ point: CGPoint, pid: Int32) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        return frame(of: element)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        let rect = CGRect(origin: position, size: size)
        return rect.width >= 1 && rect.height >= 1 ? rect : nil
    }
}

import AppKit
import ApplicationServices

/// 找到当前 App 里文字光标 / 选中文字在屏幕上的位置（Cocoa 坐标，原点在左下）。拿不到时返回 nil。
/// 通过辅助功能读取"选中范围"的边框：没有选中时就是光标所在处，有选中时是选中文字的范围。
/// 参考 Ditto 的 "At Caret" 弹出位置。剪贴板面板和翻译窗口共用。
///
/// 依次尝试：
/// 1. 选中范围（`AXSelectedTextRange` + `AXBoundsForRange`）：原生 App、大多数网页；
/// 2. 文字标记（`AXSelectedTextMarkerRange` + `AXBoundsForTextMarkerRange`）：Chromium / WebKit 的部分输入框；
/// 3. Electron App（QQ、微信、VS Code 等）默认不向辅助功能暴露界面：打开它的辅助功能开关
///    （`AXManualAccessibility`，不支持时用 `AXEnhancedUserInterface`），等界面准备好再读。
///    每个进程只开一次、之后保持开着（关掉的话下次又要等）。
///    思路参考 references/snow-apps/snow-crates/crates/snow-ui-selector/src/macos/activation_flags.rs（GPL，只借鉴思路）。
///
/// 自己画文字、完全不支持辅助功能的编辑器（例如 Sublime Text）拿不到光标位置。
@MainActor
public enum TextCaretLocator {
    /// 打开辅助功能开关后，最多等这么久让 App 建好界面
    static let activationWait: Duration = .milliseconds(300)
    static let pollInterval: Duration = .milliseconds(30)
    /// 已经尝试打开过辅助功能开关的进程
    private static var activated: Set<pid_t> = []

    /// 文字光标处
    public static func caretRect() async -> CGRect? {
        await locate()
    }

    /// 选中文字的范围（多行时是包住所有行的矩形）
    public static func selectionRect() async -> CGRect? {
        await locate()
    }

    private static func locate() async -> CGRect? {
        if let rect = currentRect() {
            return rect
        }
        guard let app = NSWorkspace.shared.frontmostApplication, activateAccessibility(of: app.processIdentifier)
        else { return nil }
        let deadline = ContinuousClock.now + activationWait
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            if let rect = currentRect() {
                return rect
            }
        }
        return nil
    }

    private static func currentRect() -> CGRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard let focused = copy(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        // CFGetTypeID 已确认类型
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        let frame = frame(of: element)
        if let rect = candidates(element).first(where: { isPlausible($0, in: frame) }) {
            return flipped(rect)
        }
        // 在输入框里但拿不到光标位置（例如 QQ 的输入框报告 (0, 屏幕高度) 这种无效坐标）：
        // 用输入框左上角的第一行代替（空输入框的光标就在那里）
        let role = copy(element, kAXRoleAttribute) as? String
        if let frame, let role, textInputRoles.contains(role) {
            return flipped(CGRect(x: frame.minX, y: frame.minY, width: 0, height: min(frame.height, 22)))
        }
        return nil
    }

    private static let textInputRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]

    /// 依次尝试的光标位置（辅助功能坐标，原点在主屏左上角）
    private static func candidates(_ element: AXUIElement) -> [CGRect] {
        var result: [CGRect] = []
        if let range = copy(element, kAXSelectedTextRangeAttribute) {
            if let rect = bounds(element, kAXBoundsForRangeParameterizedAttribute, range) {
                result.append(rect)
            }
            // 光标（空选区）的边框有的 App 给不出来：改用光标前一个字的右边缘
            if let previous = previousCharacter(range),
               let rect = bounds(element, kAXBoundsForRangeParameterizedAttribute, previous) {
                result.append(CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height))
            }
        }
        if let markers = copy(element, "AXSelectedTextMarkerRange"),
           let rect = bounds(element, "AXBoundsForTextMarkerRange", markers) {
            result.append(rect)
        }
        return result
    }

    private static func previousCharacter(_ range: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
        var value = CFRange()
        guard AXValueGetValue(unsafeDowncast(range, to: AXValue.self), .cfRange, &value), value.length == 0, value.location > 0
        else { return nil }
        var previous = CFRange(location: value.location - 1, length: 1)
        return AXValueCreate(.cfRange, &previous)
    }

    /// 像不像光标：不是全 0 大小、不超过几行高、在输入框范围内
    private static func isPlausible(_ rect: CGRect, in frame: CGRect?) -> Bool {
        guard rect.width > 0 || rect.height > 0, rect.height <= 120 else { return false }
        guard let frame else { return true }
        return frame.insetBy(dx: -8, dy: -8).intersects(rect.insetBy(dx: -1, dy: -1))
    }

    /// 元素的边框（辅助功能坐标）
    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = copy(element, kAXPositionAttribute), let size = copy(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// 参数化属性返回的边框（辅助功能坐标），无效时返回 nil
    private static func bounds(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CGRect? {
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeDowncast(bounds, to: AXValue.self), .cgRect, &rect), rect.width >= 0 else { return nil }
        return rect
    }

    /// 打开 Electron / Chromium App 的辅助功能开关。真的新打开了才返回 true（值得等一等再读）。
    private static func activateAccessibility(of pid: pid_t) -> Bool {
        guard pid != getpid(), !activated.contains(pid) else { return false }
        activated.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        // 只处理声明了 AXManualAccessibility 的 App（Electron / Chromium），不去动普通 App 的 AXEnhancedUserInterface
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(app, &names) == .success,
              let list = names as? [String], list.contains("AXManualAccessibility") else { return false }
        for flag in ["AXManualAccessibility", "AXEnhancedUserInterface"] where list.contains(flag) {
            if copy(app, flag) as? Bool == true {
                return false
            }
            // 有的 App 写入时报错但实际生效了（Firefox），以读回的值为准
            _ = AXUIElementSetAttributeValue(app, flag as CFString, kCFBooleanTrue)
            if copy(app, flag) as? Bool == true {
                return true
            }
        }
        return false
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// 辅助功能坐标原点在主屏左上角，转换成 Cocoa 坐标（原点在主屏左下角）
    private static func flipped(_ rect: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let converted = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        // 部分 App 返回的坐标明显无效（不在任何屏幕上）
        guard NSScreen.screens.contains(where: { $0.frame.intersects(converted.insetBy(dx: -2, dy: -2)) }) else {
            return nil
        }
        return converted
    }
}

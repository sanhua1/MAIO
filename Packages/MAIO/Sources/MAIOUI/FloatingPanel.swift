import AppKit
import SwiftUI

/// 不抢焦点的浮动面板（HUD、剪贴板面板、切换器、启动器、翻译等共用）。
/// 全部用 `nonactivatingPanel`：成为键盘窗口时不会把 MAIO 激活到前台，顶部菜单栏保持原来的 App
/// （普通窗口一旦激活，macOS 会把菜单栏换成 MAIO 的「MAIO 编辑 窗口」）。需要打字的用 `acceptsKeyboard` 打开 `canBecomeKey`。
///
/// 焦点链：一个能输入的面板开着时又弹出另一个（例如在启动器里呼出剪贴板），前一个不关，
/// 后一个用 `dismiss()` 关闭时把焦点还给前一个；焦点离开 MAIO（点了别的 App）时整条链都收到 `onFocusLost`。
@MainActor
public final class FloatingPanel<Content: View>: NSPanel, FocusChainPanel {
    private let acceptsKeyboard: Bool
    /// 弹出本面板时正在用的 MAIO 面板，关闭时把焦点还给它
    weak var returnWindow: NSWindow?
    /// 为了不被前一个面板挡住临时提高了层级时，原来的层级（离开焦点链时还原）
    private var liftedFrom: NSWindow.Level?

    /// 焦点离开了 MAIO（不是转到另一个 MAIO 面板）。控制器在这里按自己的规则决定关不关
    public var onFocusLost: (() -> Void)?

    public init(rootView: Content, size: CGSize = CGSize(width: 320, height: 80), acceptsKeyboard: Bool = false) {
        self.acceptsKeyboard = acceptsKeyboard
        let style: NSWindow.StyleMask = [.borderless, .fullSizeContentView, .nonactivatingPanel]
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        // 系统的窗口阴影（和别的 App 的浮动窗口一样）。透明窗口的阴影按内容的不透明部分算，圆角面板就是圆角阴影
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.intrinsicContentSize]
        contentView = hosting
    }

    /// 按 ⌘W（主菜单「窗口 › 关闭」）时调用，交给控制器走自己的关闭流程（取消请求、把焦点还给原来的 App 等）。
    /// 无边框面板没有关闭按钮，系统默认的 `performClose` 什么也不做；不设置时 ⌘W 对这个面板无效。
    public var onCloseCommand: (() -> Void)?

    /// 无边框窗口默认不能成为 key window（无法输入文字），需要键盘输入的面板要打开。
    override public var canBecomeKey: Bool {
        acceptsKeyboard || super.canBecomeKey
    }

    override public func performClose(_ sender: Any?) {
        guard let onCloseCommand else {
            super.performClose(sender)
            return
        }
        onCloseCommand()
    }

    /// 系统按"有没有关闭按钮"判断「关闭」能不能用，无边框面板总是不能用（⌘W 不会发过来）
    override public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performClose(_:)), onCloseCommand != nil {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    /// 透明窗口的阴影形状是按当时画出来的内容算好缓存的：显示和改变大小后等内容画完再重算一次，
    /// 否则阴影会是空的或者停在旧的大小
    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        refreshShadow()
    }

    override public func orderFrontRegardless() {
        super.orderFrontRegardless()
        refreshShadow()
    }

    override public func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        refreshShadow()
    }

    /// 失去焦点后等这一轮事件处理完再看新的 key 窗口是谁（另一个面板的 makeKey 是同步的）
    override public func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            self?.focusMoved()
        }
    }

    private func focusMoved() {
        // 已经关掉（正常关闭流程）或又拿回了焦点：不用管
        guard isVisible, !isKeyWindow else { return }
        if let next = NSApp.keyWindow as? FocusChainPanel, next !== self, next.isVisible {
            if next.returnWindow == nil {
                next.returnWindow = self
                next.lift(to: level)
            }
            return
        }
        focusLeftApp()
    }

    /// 例如在启动器（popUpMenu）里呼出翻译（floating）：翻译要临时提到启动器的层级，否则被挡住
    func lift(to target: NSWindow.Level) {
        guard level < target else { return }
        liftedFrom = level
        level = target
        orderFront(nil)
    }

    private func restoreLevel() {
        if let liftedFrom {
            level = liftedFrom
        }
        liftedFrom = nil
    }

    func focusLeftApp() {
        let parent = returnWindow as? FocusChainPanel
        returnWindow = nil
        restoreLevel()
        onFocusLost?()
        if parent?.isVisible == true, parent?.isKeyWindow == false {
            parent?.focusLeftApp()
        }
    }

    /// 关闭面板。返回 true 表示焦点已经还给了弹出本面板时的那个 MAIO 面板，控制器不要再去激活原来的 App
    @discardableResult
    public func dismiss() -> Bool {
        let parent = returnWindow
        returnWindow = nil
        let wasKey = isKeyWindow
        orderOut(nil)
        restoreLevel()
        guard wasKey, let parent, parent.isVisible else { return false }
        parent.makeKeyAndOrderFront(nil)
        return true
    }

    private func refreshShadow() {
        DispatchQueue.main.async { [weak self] in
            self?.invalidateShadow()
        }
    }

    public var hostingView: NSHostingView<Content>? {
        contentView as? NSHostingView<Content>
    }

    /// 放在鼠标所在屏幕的指定相对位置（0...1，原点在左下）。
    public func place(relativeX: CGFloat = 0.5, relativeY: CGFloat = 0.5) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = hostingView?.fittingSize ?? self.frame.size
        setContentSize(size)
        setFrameOrigin(CGPoint(
            x: frame.minX + (frame.width - size.width) * relativeX,
            y: frame.minY + (frame.height - size.height) * relativeY,
        ))
    }
}

/// 焦点链上的面板（`FloatingPanel` 是泛型，用协议来认出别的面板）
@MainActor
protocol FocusChainPanel: NSWindow {
    var returnWindow: NSWindow? { get set }
    func lift(to target: NSWindow.Level)
    func focusLeftApp()
}
